#!/usr/bin/env ruby
#
#  check-k8s
#
# DESCRIPTION:
#  This plugin checks the health of pods on Kubernetes
#
#
# OUTPUT:
#   json
#
# PLATFORMS:
#   Linux
#
# USAGE:
#   Checks against the kubernetes API for health of pods, nodes etc.
#
# LICENSE:
#   Schuberg Philis <int-mcp@schubergphilis.com>
#   Released under the MIT license; see LICENSE for details


require 'json'
require 'net/http'
require 'net/https'
require 'pp'
require 'cgi'
require 'uri'
require 'openssl'
require 'socket'
require 'time'

def sensu_safe(string)
  string.gsub(/[^\w\.-]+/,'_')
end

# :nocov:
def send_event(event)
  if ENV['K8S_DEBUG'] == 'true'
    puts event
  else
    s = TCPSocket.open('localhost', 3030)
    s.puts JSON.generate(event)
    s.close
  end
end
# :nocov:

# :nocov:
def query stuff
  if @incluster
    contenturi = URI.parse("https://kubernetes.default")
    req = Net::HTTP::Get.new(stuff)
    token = File.read('/var/run/secrets/kubernetes.io/serviceaccount/token').strip
    req['Authorization'] = "Bearer #{token}"
    https = Net::HTTP.new(contenturi.host, contenturi.port)
    https.read_timeout = ENV['K8S_READ_TIMEOUT'] || 10
    https.open_timeout = ENV['K8S_OPEN_TIMEOUT'] || 10
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
    resp = https.start { |cx| cx.request(req) }
    JSON.load(resp.body)
  else
    host, port = (ENV['K8S_ENDPOINT'] || 'localhost:8001').split(':')
    http = Net::HTTP.new(host, port)
    http.read_timeout = ENV['K8S_READ_TIMEOUT'] || 10
    http.open_timeout = ENV['K8S_OPEN_TIMEOUT'] || 10
    request = Net::HTTP::Get.new(stuff)
    JSON.load(http.request(request).body)
  end
end
# :nocov:

class K8sClient
  attr_accessor :pod_groups, :filter, :namespaces, :prefix, :errors, :nodes, :incluster, :reported_by, :node_data, :now, :pod_count, :pod_capacity, :monitoring_prefix
  def initialize filter,prefix,reported_by
    @pod_groups = {}
    @pod_count = 0
    @namespaces = []
    @node_data = []
    @pod_capacity= 0
    @filter = filter
    @prefix = prefix
    @nodes = 0
    @errors = false
    @incluster = false
    @reported_by = reported_by
    @now = Time.now.to_i
    @monitoring_prefix = {}
  end

  def build_event(event)
    event['reported_by'] = @reported_by
    event['occurrences'] = 3
    event['source'] = sensu_safe(event['source'])
    event['name'] = sensu_safe(event['name'])
    event
  end

  def pod_fqdn pod
    "#{pod['metadata']['namespace']}.#{pod['metadata']['name']}"
  end

  def get_pods namespace
    pods = query("/api/v1/namespaces/#{namespace}/pods")['items']
    return pods ? pods : []
  end

  def get_pod_count
    pods = query('/api/v1/pods')['items']
    @pod_count = pods ? pods.count : 0
  end

  def count_nodes
    query("/api/v1/nodes")['items'].each do |node|
      if node['status']['conditions'].find {|x| x['type'] == 'Ready' && x['status'] == "True"}
        @nodes += 1
      end
    end
  end

  def get_nodes
    nodes = query("/api/v1/nodes")['items']
    @node_data = nodes ? nodes : []
  end

  def get_pod_capacity
    @node_data.each do |node|
      @pod_capacity += node['status']['allocatable']['pods'].to_i
    end
  end

  def check_pod_capacity
    min_free_pods = 10
    if (@pod_capacity - min_free_pods) < @pod_count
      status = 2
      output = "CRIT: Using #{@pod_count}/#{@pod_capacity} pods!"
    else
      status = 0
      output = "OK: Using #{@pod_count}/#{@pod_capacity} pods!"
    end
    {
      'output' => output,
      'name' => 'check_pod_capacity',
      'source' => @prefix,
      'status' => status
    }
  end

  def check_nodes
    ready_nodes = []
    failed_nodes = []
    dead_nodes = []
    max_seconds = 1800
    @node_data.each do |node|
      node['status']['conditions'].each do |status|
        if status['type'] == 'Ready'
            hostname = node['metadata']['labels']['kubernetes.io/hostname']
          if status['status'] == 'True'
            ready_nodes << hostname
          else
            seconds = @now - Time.parse(status['lastHeartbeatTime']).to_i
            node_status = "#{hostname} last heartbeat was #{seconds} seconds ago!"
            if seconds > max_seconds
              dead_nodes << node_status
            end
            failed_nodes << node_status
          end
        end
      end
    end
    if ready_nodes.count >= 1
      if failed_nodes.count == 0
        output = "OK: All nodes are ready! Nodes: #{ready_nodes.join(',')}"
        status = 0
      elsif dead_nodes.count != 0
        output = "CRIT: There are #{ready_nodes.count} nodes ready. Dead nodes: #{failed_nodes.join(',')}"
        status = 2
      else
        output = "WARN: There are #{ready_nodes.count} nodes ready. Failed nodes: #{failed_nodes.join(',')}"
        status = 1
      end
    else
      output = "CRIT: There are no nodes ready! Failed nodes: #{failed_nodes.join(',')}"
      status = 2
    end

    {
      'output' => output,
      'name' => 'check_kube_nodes_ready',
      'source' => @prefix,
      'status' => status
    }
  end

  def pods_highly_available(pod_data)
    total_pod_count = pod_data['pods'].count

    if @nodes >= 2 and total_pod_count > 1
      expected_nodes = 2
    else
      expected_nodes = 1
    end

    healthy_pods = pod_data['pods'].select { |pod| pod['status'] == 0 }

    healthy_nodes = []
    healthy_pods.uniq { |pod| pod['node'] }.each do |pod|
      node = @node_data.select { |node| node['metadata']['name'] == pod['node'] }.first
      healthy_nodes << pod['node'] if node['status']['conditions'].find { |x| x['type'] == 'Ready' && x['status'] == 'True' }
    end

    node_count = healthy_nodes.count

    if not node_count >= expected_nodes
      ha_check = {
        "output" => "Pods are not highly available! Nodes: #{node_count}/#{@nodes}",
        "status" => 2
      }
    else
      ha_check = {
        "output" => "Pods are running highly available. Nodes: #{node_count}/#{@nodes}",
        "status" => 0
      }
    end

    [ha_check, total_pod_count, node_count]
  end

  def get_namespaces
    namespaces = query("/api/v1/namespaces?labelSelector=#{@filter}")['items']
    if namespaces
      namespaces.each do |namespace|
        name = namespace['metadata']['name']
        @namespaces << name
        if namespace['metadata']['labels'].key?('monitoring_prefix')
          @monitoring_prefix[name] = namespace['metadata']['labels']['monitoring_prefix']
        end
      end
    end
  end

  def check_pod pod
    pod_name = pod_fqdn(pod)
    namespace = pod['metadata']['namespace']
    node = pod['spec']['nodeName']

    if @monitoring_prefix.key?(namespace)
      prefix = @monitoring_prefix[namespace]
    else
      prefix = @prefix
    end

    if not ['Running', 'Succeeded'].include? pod['status']['phase']
      output = "is not running!"
      status = 2
    elsif pod['status']['conditions'].find {|x| x['type'] == 'Ready' && x['status'] == "False" && x['reason'] != 'PodCompleted'}
      output = "is not ready!"
      status = 2
    else
      output = "is healthy!"
      status = 0
    end
    {
      'output' => "#{pod_name} #{output} Node: #{node}",
      'status' => status,
      'node' => node,
      'source' => "#{prefix}.#{namespace}"
    }
  end

  def pod_group_name pod
    kind      = ""
    name      = ""
    namespace = pod['metadata']['namespace']

    # Kubernetes >= v1.9.x uses .metadata.ownerReferences to determine object owner
    if (not pod['metadata']['ownerReferences'].nil?)
      kind = pod['metadata']['ownerReferences'][0]['kind'].downcase
      name = pod['metadata']['ownerReferences'][0]['name'].downcase

    # Kubernetes < v1.9.x relies on an annotation to determine object owner
    else
      return nil if (
          pod['metadata']['annotations'].nil? ||
          pod['metadata']['annotations']['kubernetes.io/created-by'].nil?
      )

      p = JSON.load(pod['metadata']['annotations']['kubernetes.io/created-by'])

      return nil if (
          p['reference'].nil? ||
          p['reference']['kind'].nil? ||
          p['reference']['name'].nil?
      )

      kind = p['reference']['kind'].downcase
      name = p['reference']['name'].downcase
    end

    return nil if not ['replicationcontroller', 'replicaset', 'daemonset', 'petset', 'statefulset'].include? kind

    if not ['petset', 'daemonset'].include? kind
      name = name.rpartition('-')[0..-2][0]
    end
    "#{namespace}_#{name}_#{kind}"
  end

  def run
    get_namespaces
    count_nodes

    get_nodes
    node_event = build_event(check_nodes)
    send_event(node_event)

    get_pod_count
    get_pod_capacity
    pod_capacity_event= build_event(check_pod_capacity)
    send_event(pod_capacity_event)

    @namespaces.each do |namespace|
      get_pods(namespace).each do |pod|
        reported_by = 'reported_host'
        pod_status = check_pod(pod)
        group_name = pod_group_name(pod)
        next if group_name.nil?
        if @pod_groups[group_name] == nil
          @pod_groups[group_name] = {}
          @pod_groups[group_name]['pods'] = []
          @pod_groups[group_name]['source'] = pod_status['source']
          @pod_groups[group_name]['status'] = pod_status['status']
          @pod_groups[group_name]['output'] = []
          @pod_groups[group_name]['nodes'] = []
        end
        @pod_groups[group_name]['pods'] << pod_status
        @pod_groups[group_name]['nodes'] << pod_status['node']

        if pod_status['status'] > @pod_groups[group_name]['status']
          @pod_groups[group_name]['status'] = pod_status['status']
        end

        if pod_status['status'] != 0
          @pod_groups[group_name]['output'] << pod_status['output']
        end
      end
    end

    @pod_groups.each do |name,value|
      ha_check, pod_count, node_count = pods_highly_available(value)
      if ha_check['status'] != 0
        value['status'] = ha_check['status']
        value['output'] << ha_check['output']
      end

      if value['status'] == 0
        output = "OK: All pods are healthy and highly available! Pods: #{pod_count}, Nodes: #{node_count}"
      elsif (value['status'] == 2) && (ha_check['status'] == 0)
        # We are configured to be highly available, did all our pods fail?
        fail_count = 0
        value['pods'].each do |pod|
          fail_count += 1 if pod['status'] != 0
        end

        if fail_count <= 1
          # We only lost a single pod, degrade to warning and add HA check status
          value['output'] << ha_check['output']
          errors = value['output'].join(', ')
          output = "WARN: #{errors} Pods: #{pod_count}"
          value['status'] = 1
        end
      end

      if value['status'] == 2
        errors = value['output'].join(', ')
        output = "CRIT: #{errors} Pods: #{pod_count}"
        @errors = true
      end
      event = {
                'output' => output,
                'name' => name,
                'status' => value['status'],
                'source' => value['source']
              }
      event = build_event(event)
      send_event(event)
    end
  end
end

# :nocov:
if File.basename(__FILE__) == File.basename($PROGRAM_NAME)
  filter = ARGV[0]
  prefix = ARGV[1]
  reported_by = ARGV[2]
  begin
    k8s = K8sClient.new(filter,prefix,reported_by)
    k8s.incluster =
      if ENV['K8S_ENDPOINT']
        false
      else
        true
      end
    k8s.run
    output = "Checked #{k8s.pod_groups.count} pod groups and #{k8s.namespaces.count} namespaces"
    if k8s.errors
      puts "WARN: Some checks failed! #{output}"
      exit(1)
    else
      puts "OK: All checks running smoothly! #{output}"
      exit(0)
    end
  rescue => e
    puts "CRIT: Unable to run check-k8s.rb! Uncaught #{e} exception: #{e.message}"
    puts e.backtrace
    exit(2)
  end
end
# :nocov:
