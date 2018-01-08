require 'spec_helper'
require_relative '../bin/check-k8s.rb'

require 'rspec/expectations'

def slice(hash, *keys)
  Hash[ [keys, hash.values_at(*keys)].transpose]
end

RSpec::Matchers.define :include_hash_matching do |expected|
  match do |array_of_hashes|
    array_of_hashes.any? { |element| slice(element, *expected.keys) == expected }
  end
end

def send_event(event)
  $event_list << event
end

describe K8sClient do
  before :each do
    @k8s = K8sClient.new('pagethis=true','clustername','reported_by')

    @k8s.node_data = [{
      "metadata" => {
        "name" => "node1",
        "labels" => {
          "kubernetes.io/hostname" => "node1"
        }
      },
      "status" => {
        "conditions" => [{
          "type" => "Ready",
          "status" => "True"
        }]
      }
    }, {
      "metadata" => {
        "name" => "node2",
        "labels" => {
          "kubernetes.io/hostname" => "node2"
        }
      },
      "status" => {
        "conditions" => [{
          "type" => "Ready",
          "status" => "True"
        }]
      }
    }, {
      "metadata" => {
        "name" => "node3",
        "labels" => {
          "kubernetes.io/hostname" => "node3"
        }
      },
      "status" => {
        "conditions" => [{
          "type" => "Ready",
          "status" => "True"
        }]
      }
    }]
  end
  describe 'test', :vcr do
    it 'gets a pod fqdn name with the format namespace.pod' do
      pod = { "metadata" => {
                "name" => "name",
                "namespace" => "namespace"
              }
            }
      expect(@k8s.pod_fqdn(pod)).to eql('namespace.name')
    end

    it 'counts the nodes' do
      @k8s.count_nodes
      expect(@k8s.nodes).to eql(3)
    end
    it 'ignores nodes that are not ready' do
      @k8s.count_nodes
      expect(@k8s.nodes).to eql(2)
    end
    it 'checks a single node is healthy' do
      @k8s.node_data = [
        "metadata" => {
          "labels" => {
            "kubernetes.io/hostname" => "node1"
          }
        },
        "status" => {
          "conditions" => [{
            "type" => "Ready",
            "status" => "True"
            }
          ]
        }
      ]
      expect(@k8s.check_nodes).to eql({'status' => 0,
                                       'output' => 'OK: All nodes are ready! Nodes: node1',
                                       'source' => 'clustername',
                                       'name' => 'check_kube_nodes_ready'
                                       })
    end
    it 'checks a multiple nodes are healthy' do
      @k8s.node_data = [{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node1"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "True"
              }
            ]
          }
        },{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node2"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "True"
              }
            ]
          }
        }
      ]
      expect(@k8s.check_nodes).to eql({'status' => 0,
                                       'output' => 'OK: All nodes are ready! Nodes: node1,node2',
                                       'source' => 'clustername',
                                       'name' => 'check_kube_nodes_ready'
                                       })
    end
    it 'warns if a node is unhealthy for less than 30 minutes but there are healthy nodes ready' do
      @k8s.now = Time.parse("2016-12-07T09:06:36Z").to_i
      @k8s.node_data = [{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node1"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "False",
              "lastHeartbeatTime" => "2016-12-07T09:04:36Z"
              }
            ]
          }
        },{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node2"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "True"
              }
            ]
          }
        }
      ]
      expect(@k8s.check_nodes).to eql({'status' => 1,
                                       'output' => 'WARN: There are 1 nodes ready. Failed nodes: node1 last heartbeat was 120 seconds ago!',
                                       'source' => 'clustername',
                                       'name' => 'check_kube_nodes_ready'
                                       })
    end
    it 'critical if a node hasnt been ready for more than 30 minutes' do
      @k8s.now = Time.parse("2016-12-07T09:01:36Z").to_i
      @k8s.node_data = [{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node1"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "False",
              "lastHeartbeatTime" => "2016-12-06T09:34:36Z"
              }
            ]
          }
        },{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node2"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "True"
              }
            ]
          }
        }
      ]
      expect(@k8s.check_nodes).to eql({'status' => 2,
                                       'output' => 'CRIT: There are 1 nodes ready. Dead nodes: node1 last heartbeat was 84420 seconds ago!',
                                       'source' => 'clustername',
                                       'name' => 'check_kube_nodes_ready'
                                       })
    end
    it 'critical if no nodes are ready' do
      @k8s.now = Time.parse("2016-12-07T09:32:36Z").to_i
      @k8s.node_data = [{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node1"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "False",
              "lastHeartbeatTime" => "2016-12-06T09:34:36Z"
              }
            ]
          }
        },{
          "metadata" => {
            "labels" => {
              "kubernetes.io/hostname" => "node2"
            }
          },
          "status" => {
            "conditions" => [{
              "type" => "Ready",
              "status" => "False",
              "lastHeartbeatTime" => "2016-12-06T09:34:36Z"
              }
            ]
          }
        }
      ]
      expect(@k8s.check_nodes).to eql({'status' => 2,
                                       'output' => 'CRIT: There are no nodes ready! Failed nodes: node1 last heartbeat was 86280 seconds ago!,node2 last heartbeat was 86280 seconds ago!',
                                       'source' => 'clustername',
                                       'name' => 'check_kube_nodes_ready'
                                       })
    end
    it 'gets some nodes' do
      @k8s.get_nodes
      expect(@k8s.node_data[0]['metadata']['name']).to eql('10.100.0.181')
    end
    it 'checks if a pod group is running ha' do
      @k8s.nodes = 3
      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod2 is healthy! Node: node2",
          "status" => 0,
          "node"   => "node2",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod3 is healthy! Node: node3",
          "status" => 0,
          "node"   => "node3",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1", "node2", "node3"]
      }

      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['status']).to eql(0)
      expect(check['output']).to eql('Pods are running highly available. Nodes: 3/3')
    end
    it 'finds a pod group not running ha' do
      @k8s.nodes = 3
      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod2 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod3 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1", "node1", "node1"]
      }
      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['status']).to eql(2)
      expect(check['output']).to eql('Pods are not highly available! Nodes: 1/3')
    end
    it 'only makes sure that only 2 nodes are needed to be ha' do
      @k8s.nodes = 6
      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod2 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod3 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod4 is healthy! Node: node2",
          "status" => 0,
          "node"   => "node2",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod5 is healthy! Node: node2",
          "status" => 0,
          "node"   => "node2",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod6 is healthy! Node: node2",
          "status" => 0,
          "node"   => "node2",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1", "node1", "node1", "node2", "node2", "node2"]
      }
      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['output']).to eql('Pods are running highly available. Nodes: 2/6')
      expect(check['status']).to eql(0)
    end
    it 'its ok to only be on one node if you only have one node' do
      @k8s.nodes = 1
      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod2 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod3 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1", "node1", "node1"]
      }
      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['status']).to eql(0)
      expect(check['output']).to eql('Pods are running highly available. Nodes: 1/1')
    end
    it 'one pod only needs to be on one node' do
      @k8s.nodes = 3
      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1"]
      }
      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['output']).to eql('Pods are running highly available. Nodes: 1/3')
      expect(check['status']).to eql(0)
    end
    it 'allows a single pod to fail as long as we remain highly available' do
      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod2 is not ready! Node: node2",
          "status" => 2,
          "node"   => "node2",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod3 is healthy! Node: node3",
          "status" => 0,
          "node"   => "node3",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1", "node2", "node3"]
      }

      @k8s.nodes = 3
      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['status']).to eql(0)
      expect(check['output']).to eql('Pods are running highly available. Nodes: 2/3')
    end
    it 'reports pods as not highly available when more than one fails' do
      @k8s.nodes = 3
      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is not ready! Node: node1",
          "status" => 2,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod2 is not ready! Node: node2",
          "status" => 2,
          "node"   => "node2",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod3 is healthy! Node: node3",
          "status" => 0,
          "node"   => "node3",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1", "node2", "node3"]
      }

      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['status']).to eql(2)
      expect(check['output']).to eql('Pods are not highly available! Nodes: 1/3')
    end
    it 'reports pods as not highly available when the right combination of pod and node fails' do
      @k8s.node_data = [{
        "metadata" => {
          "name" => "node1",
          "labels" => {
            "kubernetes.io/hostname" => "node1"
          }
        },
        "status" => {
          "conditions" => [{
            "type" => "Ready",
            "status" => "False"
          }]
        }
      }, {
        "metadata" => {
          "name" => "node2",
          "labels" => {
            "kubernetes.io/hostname" => "node2"
          }
        },
        "status" => {
          "conditions" => [{
            "type" => "Ready",
            "status" => "True"
          }]
        }
      }, {
        "metadata" => {
          "name" => "node3",
          "labels" => {
            "kubernetes.io/hostname" => "node3"
          }
        },
        "status" => {
          "conditions" => [{
            "type" => "Ready",
            "status" => "True"
          }]
        }
      }]

      pod_data = {
        "pods" => [{
          "output" => "testnamespace.pod1 is healthy! Node: node1",
          "status" => 0,
          "node"   => "node1",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod2 is not ready! Node: node2",
          "status" => 2,
          "node"   => "node2",
          "source" => "testcluster.testnamespace"
        }, {
          "output" => "testnamespace.pod3 is healthy! Node: node3",
          "status" => 0,
          "node"   => "node3",
          "source" => "testcluster.testnamespace"
        }],
        "source" => "testcluster.testnamespace",
        "status" => 0,
        "output" => [],
        "nodes"  => ["node1", "node2", "node3"]
      }

      @k8s.nodes = 3
      (check, _pc, _nc) = @k8s.pods_highly_available(pod_data)
      expect(check['status']).to eql(2)
      expect(check['output']).to eql('Pods are not highly available! Nodes: 1/3')
    end

    it 'checks a pod with a custom monitoring prefix' do
      @k8s.monitoring_prefix['testnamespace'] = 'sbppmick'
      pod = {
        "metadata" => {
          "name" => "testpod",
          "namespace" => "testnamespace",
        },
        "spec" => {
          "nodeName" => "node1"
        },
        "status" => {
          "phase" => "Running",
          "conditions" => [
            {
              "type" => "Ready",
              "status" => "True"
            }
          ]
        }
      }
      expect(@k8s.check_pod(pod)).to eql({"output"=>"testnamespace.testpod is healthy! Node: node1", "node"=>"node1", "status"=>0, "source"=>"sbppmick.testnamespace"})
    end

    it 'does a good health check' do
      pod = {
        "metadata" => {
          "name" => "testpod",
          "namespace" => "testnamespace",
        },
        "spec" => {
          "nodeName" => "node1"
        },
        "status" => {
          "phase" => "Running",
          "conditions" => [
            {
              "type" => "Ready",
              "status" => "True"
            }
          ]
        }
      }
      expect(@k8s.check_pod(pod)).to eql({"output"=>"testnamespace.testpod is healthy! Node: node1", "node"=>"node1", "status"=>0, "source"=>"clustername.testnamespace"})
    end
    it 'health check fails because pod is not running' do
      pod =
      {
        "metadata" => {
          "name" => "testpod",
          "namespace" => "testnamespace",
        },
        "spec" => {
          "nodeName" => "node1"
        },
        "status" => {
          "phase" => "NotRunning",
          "conditions" => [
            {
              "type" => "Ready",
              "status" => "True"
            }
          ]
        }
      }
      expect(@k8s.check_pod(pod)).to eql({"output"=>"testnamespace.testpod is not running! Node: node1", "node"=>"node1", "status"=>2, "source"=>"clustername.testnamespace"})
    end
    it 'health check fails because pod is not ready' do
      pod =
        {
        "metadata" => {
          "name" => "testpod",
          "namespace" => "testnamespace",
        },
        "spec" => {
          "nodeName" => "node1"
        },
        "status" => {
          "phase" => "Running",
          "conditions" => [
            {
              "type" => "Ready",
              "status" => "False"
            }
          ]
        }
      }
      expect(@k8s.check_pod(pod)).to eql({"output"=>"testnamespace.testpod is not ready! Node: node1", "node"=>"node1", "status"=>2, "source"=>"clustername.testnamespace"})
    end
    it 'does not fail for a succesfully completed job' do
      pod =
        {
        'metadata' => {
          'name' => 'testpod',
          'namespace' => 'testnamespace',
        },
        'spec' => {
          'nodeName' => 'node1'
        },
        'status' => {
          'phase' => 'Succeeded',
          'conditions' => [
            {
              'type' => 'Ready',
              'status' => 'False',
              'reason' => 'PodCompleted'
            }
          ]
        }
      }
      expect(@k8s.check_pod(pod)).to eql({
        'output' => 'testnamespace.testpod is healthy! Node: node1',
        'node'   => 'node1',
        'status' => 0,
        'source' => 'clustername.testnamespace'
      })
    end
    it 'does fail for a failed job' do
      pod =
        {
        'metadata' => {
          'name' => 'testpod',
          'namespace' => 'testnamespace',
        },
        'spec' => {
          'nodeName' => 'node1'
        },
        'status' => {
          'phase' => 'NotSuceeded',
          'conditions' => [
            {
              'type' => 'Ready',
              'status' => 'False',
              'reason' => 'PodCompleted'
            }
          ]
        }
      }
      expect(@k8s.check_pod(pod)).to eql({
        'output' => 'testnamespace.testpod is not running! Node: node1',
        'node'   => 'node1',
        'status' => 2,
        'source' => 'clustername.testnamespace'
      })
    end
    it 'does fail for a not completed job' do
      pod =
        {
        'metadata' => {
          'name' => 'testpod',
          'namespace' => 'testnamespace',
        },
        'spec' => {
          'nodeName' => 'node1'
        },
        'status' => {
          'phase' => 'Suceeded',
          'conditions' => [
            {
              'type' => 'Ready',
              'status' => 'False',
              'reason' => 'NotCompleted'
            }
          ]
        }
      }
      expect(@k8s.check_pod(pod)).to eql({
        'output' => 'testnamespace.testpod is not running! Node: node1',
        'node'   => 'node1',
        'status' => 2,
        'source' => 'clustername.testnamespace'
      })
    end
    it 'runs a full e2e test' do
      $event_list = []
      @k8s.run
      expect(@k8s.errors).to eql(true)
      expect($event_list).to include_hash_matching({"output"=>"OK: All pods are healthy and highly available! Pods: 1, Nodes: 1",
                                                    "status"=>0,
                                                    "source"=>"clustername.mick",
                                                    "name"=>"mick_test_replicaset",
                                                    "reported_by"=>"reported_by",
                                                    "occurrences"=>3})
      expect($event_list).to include_hash_matching({"output"=>"CRIT: Pods are not highly available! Nodes: 1/3 Pods: 3",
                                                    "name"=>"mick_masters-etcd_petset",
                                                    "status"=>2,
                                                    "source"=>"clustername.mick",
                                                    "reported_by"=>"reported_by",
                                                    "occurrences"=>3})
      expect($event_list).to include_hash_matching( {"output"=>
                                                     "CRIT: mick.masters-etcd-health-check-3862343702-n14tv is not ready! Node: 10.100.0.135, Pods are not highly available! Nodes: 1/3 Pods: 2",
                                                     "name"=>"mick_masters-etcd-health-check_replicaset",
                                                     "status"=>2,
                                                     "source"=>"clustername.mick",
                                                     "reported_by"=>"reported_by",
                                                     "occurrences"=>3})
      expect($event_list).to include_hash_matching( {"output"=>
                                                     "WARN: mick.masters-etcd-health-partial-failure-2978461092-a56bq is not ready! Node: 10.100.0.135, Pods are running highly available. Nodes: 2/3 Pods: 3",
                                                     "name"=>"mick_masters-etcd-health-partial-failure_replicaset",
                                                     "status"=>1,
                                                     "source"=>"clustername.mick",
                                                     "reported_by"=>"reported_by",
                                                     "occurrences"=>3})
      expect($event_list).to include_hash_matching( {"output"=>
                                                     "CRIT: mick.masters-etcd-health-full-failure-3862343702-n14tv is not ready! Node: 10.100.0.135, mick.masters-etcd-health-full-failure-2978461092-a56bq is not ready! Node: 10.100.0.135, Pods are not highly available! Nodes: 1/3 Pods: 3",
                                                     "name"=>"mick_masters-etcd-health-full-failure_replicaset",
                                                     "status"=>2,
                                                     "source"=>"clustername.mick",
                                                     "reported_by"=>"reported_by",
                                                     "occurrences"=>3})
      expect($event_list).to include_hash_matching( {"output"=>
                                                     "OK: All nodes are ready! Nodes: 10.100.0.135,10.100.0.190,10.100.0.204",
                                                     "name"=>"check_kube_nodes_ready",
                                                     "status"=>0,
                                                     "source"=>"clustername",
                                                     "reported_by"=>"reported_by",
                                                     "occurrences"=>3})
      expect($event_list).to include_hash_matching( {"output"=>"OK: Using 6/330 pods!",
                                                    "name"=>"check_pod_capacity",
                                                    "source"=>"clustername",
                                                    "status"=>0,
                                                    "reported_by"=>"reported_by",
                                                    "occurrences"=>3},)
    end
    it 'gets a list of filtered namespaces' do
      @k8s.get_namespaces
      expect(@k8s.namespaces).to eql(['mick'])
    end

    it 'gets a namespace with a custom prefix' do
      @k8s.get_namespaces
      expect(@k8s.namespaces).to eql(['mick'])
      expect(@k8s.monitoring_prefix['mick']).to eql('sbppmick')
    end

    it 'gets a namespace without a custom prefix' do
      @k8s.get_namespaces
      expect(@k8s.namespaces).to eql(['mick'])
      expect(@k8s.monitoring_prefix['mick']).to equal(nil)
    end

    it 'it gracefully handles no results' do
      @k8s.filter = 'pagethis=false'
      @k8s.get_namespaces
      expect(@k8s.namespaces).to eql([])
    end
    it 'it creates a unique kind-pod name' do
      pod =
        {
        "metadata" => {
          "namespace" => "mick",
          "generateName" => "nginx-deployment-1159050644-",
          "annotations" => {
            "kubernetes.io/created-by" => "{\"kind\":\"SerializedReference\",\"apiVersion\":\"v1\",\"reference\":{\"kind\":\"ReplicaSet\",\"namespace\":\"mick\",\"name\":\"nginx-deployment-1159050644\",\"uid\":\"6992622b-ad75-11e6-86ea-02004e5d0013\",\"apiVersion\":\"extensions\",\"resourceVersion\":\"227692\"}}\n"
          }
        }
      }
      expect(@k8s.pod_group_name(pod)).to eql('mick_nginx-deployment_replicaset')
    end
    it 'it handles petsets elegantly' do
      pod =
        {
        "metadata" => {
          "namespace" => "mick",
          "generateName" => "masters-etcd-",
          "annotations" => {
            "kubernetes.io/created-by" => "{\"kind\":\"SerializedReference\",\"apiVersion\":\"v1\",\"reference\":{\"kind\":\"PetSet\",\"namespace\":\"mick\",\"name\":\"masters-etcd\",\"uid\":\"98fc0685-abeb-11e6-86ea-02004e5d0013\",\"apiVersion\":\"apps\",\"resourceVersion\":\"8689\"}}\n"
          }
        }
      }
      expect(@k8s.pod_group_name(pod)).to eql('mick_masters-etcd_petset')
    end
    it 'it handles single pods without annotations not belonging to a group correctly' do
      pod =
        {
        "metadata" => {
          "namespace" => "mick",
          "generateName" => "single pod"
        }
      }
      expect(@k8s.pod_group_name(pod)).to eql(nil)
    end
    it 'it handles single pods with annotations not belonging to a group correctly' do
      pod =
        {
        "metadata" => {
          "namespace" => "mick",
          "generateName" => "single pod",
          "annotations" => '{"dns.alpha.kubernetes.io/internal":"api.internal.sbparainy1.k8s.local","kubernetes.io/config.hash":"b5a41a46f3343f6efa16b3faf9214c61","kubernetes.io/config.mirror":"b5a41a46f3343f6efa16b3faf9214c61","kubernetes.io/config.seen":"2017-10-20T09:11:05.503737927Z","kubernetes.io/config.source":"file"}'
        }
      }
      expect(@k8s.pod_group_name(pod)).to eql(nil)
    end
    it 'it ignores pods created by jobs' do
      pod =
        {
        "metadata" => {
          "namespace" => "mick",
          "generateName" => "single pod",
          "annotations" => {
            "kubernetes.io/created-by" => "{\"kind\":\"SerializedReference\",\"apiVersion\":\"v1\",\"reference\":{\"kind\":\"Job\",\"namespace\":\"mick\",\"name\":\"masters-etcd\",\"uid\":\"98fc0685-abeb-11e6-86ea-02004e5d0013\",\"apiVersion\":\"apps\",\"resourceVersion\":\"8689\"}}\n"
          }
        }
      }
      expect(@k8s.pod_group_name(pod)).to eql(nil)
    end
    it 'it ignores pods created by unknown objects' do
      pod =
        {
        "metadata" => {
          "namespace" => "mick",
          "generateName" => "single pod",
          "annotations" => {
            "kubernetes.io/created-by" => "{\"kind\":\"SerializedReference\",\"apiVersion\":\"v1\",\"reference\":{\"kind\":\"SuperAwesomeController\",\"namespace\":\"mick\",\"name\":\"masters-etcd\",\"uid\":\"98fc0685-abeb-11e6-86ea-02004e5d0013\",\"apiVersion\":\"apps\",\"resourceVersion\":\"8689\"}}\n"
          }
        }
      }
      expect(@k8s.pod_group_name(pod)).to eql(nil)
    end
    it 'it parses pods created by known objects correctly' do
      for kind in ['ReplicationController', 'ReplicaSet', 'DaemonSet', 'StatefulSet'] do
        pod =
          {
          "metadata" => {
            "namespace" => "mick",
            "generateName" => "nginx-deployment-1159050644-",
            "annotations" => {
              "kubernetes.io/created-by" => "{\"kind\":\"SerializedReference\",\"apiVersion\":\"v1\",\"reference\":{\"kind\":\"#{kind}\",\"namespace\":\"mick\",\"name\":\"nginx-deployment-1159050644\",\"uid\":\"6992622b-ad75-11e6-86ea-02004e5d0013\",\"apiVersion\":\"extensions\",\"resourceVersion\":\"227692\"}}\n"
            }
          }
        }
        expect(@k8s.pod_group_name(pod)).to eql("mick_nginx-deployment_#{kind.downcase}")
      end
    end
    it 'counts the total pods running' do
      @k8s.get_pod_count
      expect(@k8s.pod_count).to eql(6)
    end
    it 'gets the pod capacity' do
      @k8s.get_nodes
      @k8s.get_pod_capacity
      expect(@k8s.pod_capacity).to eql(330)
    end
    it 'checks if we have room for some more pods' do
      @k8s.get_nodes
      @k8s.get_pod_count
      @k8s.get_pod_capacity
      expect(@k8s.check_pod_capacity).to eql({
                                              "output"=>"OK: Using 6/330 pods!",
                                              "name"=>"check_pod_capacity",
                                              "source"=>"clustername",
                                              "status"=>0
                                             })
    end
    it 'checks if we have room for some more pods' do
      @k8s.pod_capacity = 330
      @k8s.pod_count = 200
      expect(@k8s.check_pod_capacity).to eql({
                                              "output"=>"OK: Using 200/330 pods!",
                                              "name"=>"check_pod_capacity",
                                              "source"=>"clustername",
                                              "status"=>0
                                             })
    end
    it 'gives a critical if there is less than 10 pod spots available' do
      @k8s.pod_capacity = 330
      @k8s.pod_count = 325
      expect(@k8s.check_pod_capacity).to eql({
                                              "output"=>"CRIT: Using 325/330 pods!",
                                              "name"=>"check_pod_capacity",
                                              "source"=>"clustername",
                                              "status"=>2
                                             })
    end
  end
end

describe '#sensu_safe' do
  it 'returns a safe hostname' do
    expect(sensu_safe('test-hostname:9100')).to eql('test-hostname_9100')
  end
  it 'returns a safe check name' do
    expect(sensu_safe('check_disk_/root/')).to eql('check_disk__root_')
  end
end
