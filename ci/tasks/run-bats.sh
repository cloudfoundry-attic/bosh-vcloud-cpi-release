#!/usr/bin/env bash

set -e

release_dir="$( cd $(dirname $0) && cd ../.. && pwd )"
workspace_dir="$( cd ${release_dir} && cd .. && pwd )"

source ${release_dir}/ci/tasks/utils.sh

print_git_state ${release_dir}

: ${base_os:?}
: ${BAT_NETWORKING:?}
: ${VCLOUD_VLAN:?}
: ${NETWORK_CIDR:?}
: ${NETWORK_GATEWAY:?}
: ${BATS_DIRECTOR_IP:?}
: ${BATS_STEMCELL_NAME:?}
: ${BATS_IP1:?}
: ${BATS_IP2:?}
: ${BATS_RESERVED_RANGE1:?}
: ${BATS_RESERVED_RANGE2:?}
: ${BATS_STATIC_RANGE:?}

source /etc/profile.d/chruby.sh
chruby 2.1.2

# inputs
stemcell_dir="${workspace_dir}/stemcell"
bats_dir="${workspace_dir}/bats"

echo "using bosh CLI version..."
bosh version
bosh -n target $BATS_DIRECTOR_IP

export BAT_INFRASTRUCTURE=vcloud
export BAT_VCAP_PASSWORD=c1oudc0w
export BAT_DNS_HOST=$BATS_DIRECTOR_IP
export BAT_DIRECTOR=$BATS_DIRECTOR_IP
export BAT_STEMCELL="${stemcell_dir}/stemcell.tgz"
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

pushd ${bats_dir}
  ./write_gemfile

  bundle install
  bundle exec rspec spec
popd
