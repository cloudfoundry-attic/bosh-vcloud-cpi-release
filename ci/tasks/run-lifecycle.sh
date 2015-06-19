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

##install mkisofs
#pushd bosh-cpi-release
#echo "using bosh CLI version..."
#bosh version
#bosh blobs sync
#pushd blobs
#sh ../packages/bosh_vcloud_cpi_mkisofs/packaging
#popd
#popd
#
#cd bosh-cpi-src
#
#bundle install
#bundle exec rake spec:lifecycle
