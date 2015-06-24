#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

print_git_state bosh-cpi-release

check_param base_os
check_param BAT_NETWORKING
check_param VCLOUD_VLAN
check_param NETWORK_CIDR
check_param NETWORK_GATEWAY
check_param BATS_DIRECTOR_IP
check_param BATS_STEMCELL_NAME
check_param BATS_IP1
check_param BATS_IP2
check_param BATS_RESERVED_RANGE1
check_param BATS_RESERVED_RANGE2
check_param BATS_STATIC_RANGE

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

echo "using bosh CLI version..."
bosh version
bosh -n target $BATS_DIRECTOR_IP

export BAT_INFRASTRUCTURE=vcloud
export BAT_VCAP_PASSWORD=c1oudc0w
export BAT_DNS_HOST=$BATS_DIRECTOR_IP
export BAT_DIRECTOR=$BATS_DIRECTOR_IP
export BAT_STEMCELL="${PWD}/stemcell/stemcell.tgz"
export BAT_DEPLOYMENT_SPEC="${PWD}/${base_os}-${BAT_NETWORKING}-bats-config.yml"

cat > $BAT_DEPLOYMENT_SPEC <<EOF
---
cpi: vcloud
properties:
  uuid: $(bosh status --uuid)
  second_static_ip: ${BATS_IP2}
  pool_size: 1
  stemcell:
    name: ${BATS_STEMCELL_NAME}
    version: latest
  instances: 1
  networks:
    - name: static
      static_ip: ${BATS_IP1}
      type: manual
      cidr: ${NETWORK_CIDR}
      reserved:
        - ${BATS_RESERVED_RANGE1}
        - ${BATS_RESERVED_RANGE2}
      static: [${BATS_STATIC_RANGE}]
      gateway: ${NETWORK_GATEWAY}
      vlan: ${VCLOUD_VLAN}
  vapp_name: bats-concourse-${base_os}-vapp
EOF

ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa

cd bats
bundle install
bundle exec rspec spec
