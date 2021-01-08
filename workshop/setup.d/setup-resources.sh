#!/bin/bash

curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/0.17.0/install.sh | bash -s 0.17.0
kubectl create -f https://raw.githubusercontent.com/TYsewyn/Getting-started-with-Spring-Cloud/master/redis-operator.yaml
kubectl create -f https://raw.githubusercontent.com/TYsewyn/Getting-started-with-Spring-Cloud/master/redis.yaml