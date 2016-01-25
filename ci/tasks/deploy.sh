#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param base_os
check_param network_type_to_test
check_param VCLOUD_VLAN
check_param VCLOUD_HOST
check_param VCLOUD_USER
check_param VCLOUD_PASSWORD
check_param VCLOUD_ORG
check_param VCLOUD_VDC
check_param NETWORK_CIDR
check_param NETWORK_GATEWAY
check_param BATS_DIRECTOR_IP

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

semver=`cat version-semver/number`
cpi_release_name="bosh-vcloud-cpi"
working_dir=$PWD

manifest_prefix=${base_os}-${network_type_to_test}-director
manifest_dir="${working_dir}/director-state-file"
manifest_filename=${manifest_prefix}-manifest.yml

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
      vapp: bosh-concourse-director-${base_os}

disk_pools:
  - name: disks
    disk_size: 20_000

networks:
  - name: private
    type: manual
    subnets:
      - range: ${NETWORK_CIDR}
        gateway: ${NETWORK_GATEWAY}
        dns: [8.8.8.8]
        cloud_properties: {name: ${VCLOUD_VLAN}}

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
      - {name: powerdns, release: bosh}
      - {name: vcloud_cpi, release: bosh-vcloud-cpi}

    resource_pool: vms
    persistent_disk_pool: disks

    networks:
      - {name: private, static_ips: [${BATS_DIRECTOR_IP}]}

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
        address: ${BATS_DIRECTOR_IP}
        port: 25250
        provider: dav
        director: {user: director, password: director-password}
        agent: {user: agent, password: agent-password}

      director:
        address: 127.0.0.1
        name: my-bosh
        db: *db
        cpi_job: vcloud_cpi
        max_threads: 10

      vcd: &vcd # <--- Replace values below
        url: ${VCLOUD_HOST}
        user: ${VCLOUD_USER}
        password: ${VCLOUD_PASSWORD}
        entities:
          organization: ${VCLOUD_ORG}
          virtual_datacenter: ${VCLOUD_VDC}
          vapp_catalog: bosh-concourse-director-${base_os}-catalog
          media_catalog: bosh-concourse-director-${base_os}-catalog
          media_storage_profile: '*'
          vm_metadata_key: vm-metadata-key
        control: {wait_max: 900}

      hm:
        http: {user: hm, password: hm-password}
        director_account: {user: admin, password: admin}
        resurrector_enabled: true

      dns:
        address: 127.0.0.1
        db: *db

      agent: {mbus: "nats://nats:nats-password@${BATS_DIRECTOR_IP}:4222"}

      ntp: &ntp [0.pool.ntp.org, 1.pool.ntp.org]

cloud_provider:
  template: {name: vcloud_cpi, release: ${cpi_release_name}}

  mbus: "https://mbus:mbus-password@${BATS_DIRECTOR_IP}:6868"

  properties:
    vcd: *vcd
    agent: {mbus: "https://mbus:mbus-password@0.0.0.0:6868"}
    blobstore: {provider: local, path: /var/vcap/micro_bosh/data/cache}
    ntp: *ntp
EOF

initver=$(cat bosh-init/version)
bosh_init="${working_dir}/bosh-init/bosh-init-${initver}-linux-amd64"
chmod +x $bosh_init

echo "deleting existing BOSH Director VM..."
$bosh_init delete ${manifest_dir}/${manifest_filename}

echo "deploying BOSH..."
$bosh_init deploy ${manifest_dir}/${manifest_filename}
