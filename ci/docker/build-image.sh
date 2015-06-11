#!/bin/bash

set -e

DOCKER_IMAGE=${DOCKER_IMAGE:-bosh/vcloud-cpi-release}

docker login --username=bosh --email=cf-bosh-eng@pivotal.io

echo "Building docker image..."
docker build -t $DOCKER_IMAGE .

echo "Pushing docker image to '$DOCKER_IMAGE'..."
docker push $DOCKER_IMAGE
