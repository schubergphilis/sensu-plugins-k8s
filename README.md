# Sensu Plugin Check-k8s

## Description
Sensu plugin used to check the health of pods in a kuberenetes cluster based on namespaces. Setting the label 'pagethis=true' on a namespace will tell sensu to start monitoring it. Results are sent using the sensu socket so that each namespace and group of pods has a seperate check result.


## Features
  * Check that pod is running
  * Check that pod is healthy
  * Check that pod is ready
  * Check that group of pods are running highly available
  * Seperate results per namespace and pod group
  * Use in-cluster authentication to connect to the kubernetes api

## Usage
```
check-k8s.rb filter prefix reported_by

# Example
check-k8s.rb pagethis=true mcpamrussell1 sensuclient
```

## Environment variables

* `K8S_DEBUG=true` - Output the events instead of sending them to sensu
* `K8S_READ_TIMEOUT=10` - Set the http connection read timeout (default is 10 seconds)
* `K8S_OPEN_TIMEOUT=10` - Set the http connection open timeout (default is 10 seconds)
* `K8S_ENDPOINT=localhost:8001` - Set the kubernetes endpoint when not using incluster auth (default is `localhost:8000`)

## Local development

Install dependencies with bundle
```
bundle install
```

Run tests
```
bundle exec rspec
```

Run tests with docker
```
bash test.sh
```
