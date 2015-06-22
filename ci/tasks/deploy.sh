#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

print_git_state bosh-cpi-release

check_param base_os
check_param network_type_to_test
check_param BAT_DIRECTOR
check_param BOSH_VCLOUD_CPI_NETWORK_CIDR
check_param BOSH_VCLOUD_CPI_GATEWAY
check_param BOSH_VCLOUD_CPI_NET_ID
check_param BOSH_VCLOUD_CPI_URL
check_param BOSH_VCLOUD_CPI_USER
check_param BOSH_VCLOUD_CPI_PASSWORD
check_param BOSH_VCLOUD_CPI_ORG_AND_VDC
check_param bats_BOSH_VCLOUD_CPI_CATALOG
check_param bats_BOSH_VCLOUD_CPI_VM_METADATA_KEY

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

semver=`cat version-semver/number`
cpi_release_name="bosh-vcloud-cpi"
working_dir=$PWD
manifest_dir="${working_dir}/tmp"
manifest_prefix=${base_os}-${network_type_to_test}-director-manifest
manifest_filename=${manifest_prefix}.yml

mkdir $manifest_dir
cat > "${manifest_dir}/${manifest_filename}" <<EOF
---
name: bosh

releases:
  - name: bosh
    url: file://${working_dir}/bosh-release/release.tgz
  - name: ${cpi_release_name}
    url: file://${working_dir}/bosh-cpi-dev-artifacts/${cpi_release_name}-${semver}.tgz

resource_pools:
  - name: vms
    network: private
    stemcell:
      url: file://${working_dir}/stemcell/stemcell.tgz
    cloud_properties:
      cpu: 2
      ram: 4_096
      disk: 20_000
    env:
      bosh:
        # c1oudc0w is a default password for vcap user
        password: "$6$4gDD3aV0rdqlrKC$2axHCxGKIObs6tAmMTqYCspcdvQXh3JJcvWOY2WGb4SrdXtnCyNaWlrf3WEqvYR2MYizEGp3kMmbpwBC6jsHt0"

disk_pools:
  - name: disks
    disk_size: 20_000

networks:
  - name: private
    type: manual
    subnets:
      - range: ${BOSH_VCLOUD_CPI_NETWORK_CIDR}
        gateway: ${BOSH_VCLOUD_CPI_GATEWAY}
        dns: [8.8.8.8]
        cloud_properties: {name: ${BOSH_VCLOUD_CPI_NET_ID}}

jobs:
  - name: bosh
    instances: 1

    templates:
      - {name: nats, release: bosh}
      - {name: redis, release: bosh}
      - {name: postgres, release: bosh}
      - {name: blobstore, release: bosh}
      - {name: director, release: bosh}
      - {name: health_monitor, release: bosh}
      - {name: cpi, release: bosh-vcloud-cpi}

    resource_pool: vms
    persistent_disk_pool: disks

    networks:
      - {name: private, static_ips: [${BAT_DIRECTOR}]}

    properties:
      nats:
        address: 127.0.0.1
        user: nats
        password: nats-password

      redis:
        listen_addresss: 127.0.0.1
        address: 127.0.0.1
        password: redis-password

      postgres: &db
        host: 127.0.0.1
        user: postgres
        password: postgres-password
        database: bosh
        adapter: postgres

      blobstore:
        address: ${BAT_DIRECTOR}
        port: 25250
        provider: dav
        director: {user: director, password: director-password}
        agent: {user: agent, password: agent-password}

      director:
        address: 127.0.0.1
        name: my-bosh
        db: *db
        cpi_job: cpi
        max_threads: 1

      vcd: &vcd # <--- Replace values below
        url: ${BOSH_VCLOUD_CPI_URL}
        user: ${BOSH_VCLOUD_CPI_USER}
        password: ${BOSH_VCLOUD_CPI_PASSWORD}
        entities:
          organization: ${BOSH_VCLOUD_CPI_ORG_AND_VDC}
          virtual_datacenter: ${BOSH_VCLOUD_CPI_ORG_AND_VDC}
          vapp_catalog: ${bats_BOSH_VCLOUD_CPI_CATALOG}
          media_catalog: ${bats_BOSH_VCLOUD_CPI_CATALOG}
          media_storage_profile: '*'
          vm_metadata_key: ${bats_BOSH_VCLOUD_CPI_VM_METADATA_KEY}
        control: {wait_max: 900}

      hm:
        http: {user: hm, password: hm-password}
        director_account: {user: admin, password: admin}
        resurrector_enabled: true

      agent: {mbus: "nats://nats:nats-password@${BAT_DIRECTOR}:4222"}

      ntp: &ntp [0.pool.ntp.org, 1.pool.ntp.org]

cloud_provider:
  template: {name: cpi, release: ${cpi_release_name}}

  mbus: "https://mbus:mbus-password@${BAT_DIRECTOR}:6868"

  properties:
    vcd: *vcd
    agent: {mbus: "https://mbus:mbus-password@0.0.0.0:6868"}
    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}
    ntp: *ntp
EOF

set +e
echo "if previous runs state file exists, copy into: ${manifest_dir}"
cp bosh-concourse-ci/pipelines/${cpi_release_name}/${manifest_prefix}-state.json ${manifest_dir}/
set -e

initver=$(cat bosh-init/version)
bosh-init="${working_dir}/bosh-init/bosh-init-${initver}-linux-amd64"
chmod +x $bosh-init

echo "deleting existing BOSH Director VM..."
$bosh-init delete ${manifest_dir}/${manifest_filename}

echo "deploying BOSH..."
$bosh-init deploy ${manifest_dir}/${manifest_filename}

