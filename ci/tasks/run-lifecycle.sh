#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param VCLOUD_HOST
check_param VCLOUD_USER
check_param VCLOUD_PASSWORD
check_param VCLOUD_VLAN
check_param VCLOUD_VDC
check_param NETWORK_NETMASK
check_param NETWORK_DNS
check_param NETWORK_GATEWAY
check_param LIFECYCLE_IP1
check_param LIFECYCLE_IP2

export BOSH_VCLOUD_CPI_STEMCELL=$PWD/stemcell/stemcell.tgz
export BOSH_VCLOUD_CPI_URL=${VCLOUD_HOST}
export BOSH_VCLOUD_CPI_USER=${VCLOUD_USER}
export BOSH_VCLOUD_CPI_PASSWORD=${VCLOUD_PASSWORD}
export BOSH_VCLOUD_CPI_NET_ID=${VCLOUD_VLAN}
export BOSH_VCLOUD_CPI_ORG=${VCLOUD_VDC}
export BOSH_VCLOUD_CPI_VDC=${VCLOUD_VDC}
export BOSH_VCLOUD_CPI_VAPP_CATALOG=bosh-concourse-lifecycle-catalog
export BOSH_VCLOUD_CPI_VAPP_NAME=bosh-concourse-lifecycle-vapp
export BOSH_VCLOUD_CPI_MEDIA_CATALOG=bosh-concourse-lifecycle-catalog
export BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE=*
export BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE=SSD-Accelerated
export BOSH_VCLOUD_CPI_VM_METADATA_KEY=vm-metadata-key
export BOSH_VCLOUD_CPI_IP=$LIFECYCLE_IP1
export BOSH_VCLOUD_CPI_IP2=$LIFECYCLE_IP2
export BOSH_VCLOUD_CPI_NETMASK=NETWORK_NETMASK
export BOSH_VCLOUD_CPI_DNS=NETWORK_DNS
export BOSH_VCLOUD_CPI_GATEWAY=NETWORK_GATEWAY

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

mkdir /tmp/vcd-cpi-test                                     # So that fly intercepts can tail it without waiting for
echo "Awaiting first test run..." > /tmp/vcd-cpi-test/debug # the tests to start outputting to it

pushd bosh-cpi-release
  echo "using bosh CLI version..."
  bosh version
  bosh create release --name local --version 0.0.0 --with-tarball --force
popd

echo "compiling mkisofs"
mkdir iso_image_install
pushd iso_image_install
  tar -xvzf ../bosh-cpi-release/dev_releases/local/local-0.0.0.tgz
  tar -xvzf packages/bosh_vcloud_cpi_mkisofs.tgz
  chmod +x packaging
  BOSH_INSTALL_TARGET=$PWD ./packaging &> mkisofs_compilation.log
  export PATH=$PATH:$PWD/bin
popd
echo "installed mkisofs at `which mkisofs`"

pushd bosh-cpi-src
  bundle install
  bundle exec rake spec:lifecycle
popd
