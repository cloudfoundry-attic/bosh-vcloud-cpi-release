#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

print_git_state bosh-cpi-release

check_param base_os
check_param BAT_NETWORKING
check_param BAT_DIRECTOR
check_param BOSH_VCLOUD_CPI_NETWORK_CIDR
check_param BOSH_VCLOUD_CPI_GATEWAY
check_param BOSH_VCLOUD_CPI_NET_ID
check_param BOSH_VCLOUD_BAT_STEMCELL_NAME
check_param BOSH_VCLOUD_FIRST_BAT_IP
check_param BOSH_VCLOUD_SECOND_BAT_IP
check_param BOSH_VCLOUD_NETWORK_RESERVED_1
check_param BOSH_VCLOUD_NETWORK_RESERVED_2
check_param BOSH_VCLOUD_NETWORK_STATIC

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

echo "using bosh CLI version..."
bosh version
bosh -n target $BAT_DIRECTOR

export BAT_VCAP_PASSWORD=c1oudc0w
export BAT_INFRASTRUCTURE=vcloud
cpi_release_name=bosh-${BAT_INFRASTRUCTURE}-cpi
export BAT_DNS_HOST=$BAT_DIRECTOR
export BAT_STEMCELL="${PWD}/stemcell/stemcell.tgz"
export BAT_DEPLOYMENT_SPEC="${PWD}/${base_os}-${BAT_NETWORKING}-bats-config.yml"

ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa

cat > $BAT_DEPLOYMENT_SPEC <<EOF
---
cpi: vcloud
properties:
  uuid: $(bosh status --uuid)
  second_static_ip: ${BOSH_VCLOUD_SECOND_BAT_IP}
  pool_size: 1
  stemcell:
    name: ${BOSH_VCLOUD_BAT_STEMCELL_NAME}
    version: latest
  instances: 1
  networks:
    - name: static
      static_ip: ${BOSH_VCLOUD_FIRST_BAT_IP}
      type: manual
      cidr: ${BOSH_VCLOUD_CPI_NETWORK_CIDR}
      reserved:
        - ${BOSH_VCLOUD_NETWORK_RESERVED_1}
        - ${BOSH_VCLOUD_NETWORK_RESERVED_2}
      static: [${BOSH_VCLOUD_NETWORK_STATIC}]
      gateway: ${BOSH_VCLOUD_CPI_GATEWAY}
      vlan: ${BOSH_VCLOUD_CPI_NET_ID}
  vapp_name: bats-concourse-${base_os}-vapp
EOF

cd bats
bundle install
bundle exec rspec spec
