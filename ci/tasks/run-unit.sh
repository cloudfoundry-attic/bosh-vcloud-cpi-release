#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

pushd bosh-cpi-src
  bundle install
  bundle exec rake spec:unit
popd
