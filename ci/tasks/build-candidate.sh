#!/usr/bin/env bash

set -e

semver=`cat version-semver/number`

pushd bosh-cpi-src
  echo "running unit tests"
  pushd src/bosh_vcloud_cpi
    bundle install
    bundle exec rspec spec/unit
  popd

  echo "installing the latest bosh_cli"
  gem install bosh_cli --no-ri --no-rdoc

  echo "using bosh CLI version..."
  bosh version

  cpi_release_name="bosh-vcloud-cpi"

  echo "building CPI release..."
  bosh create release --name $cpi_release_name --version $semver --with-tarball
popd

mv bosh-cpi-src/dev_releases/$cpi_release_name/$cpi_release_name-$semver.tgz candidate/
