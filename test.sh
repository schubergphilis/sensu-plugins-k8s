#!/bin/bash

set -e

docker build -t saas/sensu-plugins-k8s .
docker run --rm saas/sensu-plugins-k8s rspec -c -f d
