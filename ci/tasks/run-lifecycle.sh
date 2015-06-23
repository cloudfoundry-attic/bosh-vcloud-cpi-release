#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param BOSH_VCLOUD_CPI_URL
check_param BOSH_VCLOUD_CPI_USER
check_param BOSH_VCLOUD_CPI_PASSWORD
check_param BOSH_VCLOUD_CPI_NET_ID
check_param BOSH_VCLOUD_CPI_ORG
check_param BOSH_VCLOUD_CPI_VDC
check_param BOSH_VCLOUD_CPI_VAPP_CATALOG
check_param BOSH_VCLOUD_CPI_VAPP_NAME
check_param BOSH_VCLOUD_CPI_MEDIA_CATALOG
check_param BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE
check_param BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE
check_param BOSH_VCLOUD_CPI_VM_METADATA_KEY
check_param BOSH_VCLOUD_CPI_IP
check_param BOSH_VCLOUD_CPI_IP2
check_param BOSH_VCLOUD_CPI_NETMASK
check_param BOSH_VCLOUD_CPI_DNS
check_param BOSH_VCLOUD_CPI_GATEWAY

export BOSH_VCLOUD_CPI_STEMCELL=$PWD/stemcell/stemcell.tgz

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

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
