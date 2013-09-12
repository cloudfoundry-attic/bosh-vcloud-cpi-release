#!/bin/bash

set -x

STRESS_BOSH_DIRECTOR=https://172.31.100.40:25555
STRESS_BOSH_UUID=b39bd5cd-ce82-443b-9e6b-cd780e1fdcd8
STRESS_REDIS_HOST=172.31.110.1
STRESS_REDIS_PORT=6379
STRESS_REDIS_OPTS="-h $STRESS_REDIS_HOST -p $STRESS_REDIS_PORT"

BASE_IP=$1
LEVELS=$2
FACTOR=$3
TIMEOUT=$4

COMPILERS=2 # compilation nodes
IP_POOL_SIZE=$(($FACTOR*2+$COMPILERS))

# Assume we use 172.31.0.0/16 as subnet
IP_SUF0=${BASE_IP##*.}
SUBNET=${BASE_IP%.*}
IP_SUF1=${SUBNET##*.}
SUBNET=${SUBNET%.*}
BASEADDR=$(($IP_SUF1*256+$IP_SUF0))

addr2ip() {
    local suf0 suf1
    suf0=$(($1&255))
    suf1=$(($1>>8))
    echo ${SUBNET}.${suf1}.${suf0}
}

IP_RESV_LAST=$(addr2ip $((BASEADDR-1)))
IP_RESV_NEXT=$(addr2ip $((BASEADDR+IP_POOL_SIZE)))
IP_STATIC_START=$(addr2ip $BASEADDR)
IP_STATIC_END=$(addr2ip $((BASEADDR+FACTOR-1)))

STRESS_IP=$(ifconfig eth0 | grep 'inet addr:' | sed -r 's/^\s*inet addr:(\S+)\s+.*$/\1/')
STRESS_KEY=${STRESS_IP//./_}

DEPLOY_NAME=${STRESS_NAME}_${STRESS_KEY}
DEPLOYMENT_FILE=/tmp/stress-deploy.yml

set -e

export PATH=/var/vcap/packages/ruby/bin:$PATH
export BUNDLE_GEMFILE=/var/vcap/packages/bosh-cli/Gemfile
export HOME=/tmp
BOSH_CLI="bundle exec bosh -u admin -p admin -n --no-color -t $STRESS_BOSH_DIRECTOR -d $DEPLOYMENT_FILE"

cat >$DEPLOYMENT_FILE <<EOF
---
name: $DEPLOY_NAME
director_uuid: $STRESS_BOSH_UUID

release:
  name: stress
  version: latest

compilation:
  workers: $COMPILERS
  network: default
  cloud_properties:
    ram: 2048
    disk: 8096
    cpu: 4

update:
  canaries: 1
  canary_watch_time: 3000-90000
  update_watch_time: 3000-90000
  max_in_flight: 4
  max_errors: 1

networks:

- name: default
  subnets:
  - range: 172.31.0.0/16
    reserved:
    - 172.31.0.2 - $IP_RESV_LAST
    - $IP_RESV_NEXT - 172.31.255.254
    static:
    - $IP_STATIC_START - $IP_STATIC_END
    gateway: 172.31.0.1
    dns:
    - 172.31.0.1
    cloud_properties:
      name: dev1-vdc1-routed

resource_pools:

- name: stress
  network: default
  size: $FACTOR
  stemcell:
    name: bosh-stemcell
    version: 1.5.0.pre.3
  cloud_properties:
    ram: 1024
    disk: 1024
    cpu: 1
  env:
    vapp: $DEPLOY_NAME

jobs:

- name: stress
  template: stress
  instances: $FACTOR
  resource_pool: stress
  networks:
  - name: default
    static_ips:
    - $IP_STATIC_START - $IP_STATIC_END

properties:
  redis:
    host: $STRESS_REDIS_HOST
    port: $STRESS_REDIS_PORT

  stress:
    name: $STRESS_NAME

EOF

$BOSH_CLI deploy

set +e
RESULT=0
if [ $LEVELS -gt 1 ]; then
    NEXT_BASEADDR=$((BASEADDR+IP_POOL_SIZE))
    NEXT_LEVELS=$((LEVELS-1))
    SEGMENT_SIZE=0
    for ((l=0;l<$NEXT_LEVELS;l=l+1)); do
        SEGMENT_SIZE=$(($SEGMENT_SIZE+$IP_POOL_SIZE*$FACTOR**$l))
    done
    for ((i=0;i<$FACTOR;i=i+1)); do
        NEXT_IP=$(addr2ip $((BASEADDR+i)))
        NEXT_KEY=${NEXT_IP//./_}
        NEXT_BASE_IP=$(addr2ip $((NEXT_BASEADDR+SEGMENT_SIZE*i)))
        redis-cli $STRESS_REDIS_OPTS LPUSH c-$NEXT_KEY "scripts/from-redis $STRESS_REDIS_SCRIPT_KEY $NEXT_BASE_IP $NEXT_LEVELS $FACTOR" || RESULT=1
    done

    if [ -n "$TIMEOUT" ]; then
        for ((i=0;i<$FACTOR;i=i+1)); do
            NEXT_IP=$(addr2ip $((BASEADDR+i)))
            NEXT_KEY=${NEXT_IP//./_}
            id=$(redis-cli $STRESS_REDIS_OPTS --raw BRPOP r-$NEXT_KEY $TIMEOUT | tail -n +2)
            echo "ID: $id"
            [ -n "$id" ] || RESULT=1
            redis-cli $STRESS_REDIS_OPTS HGETALL s-$NEXT_KEY
        done
    fi
fi

if [ -n "$TIMEOUT" ]; then
    $BOSH_CLI delete deployment $DEPLOY_NAME --force || RESULT=1
fi

exit $RESULT