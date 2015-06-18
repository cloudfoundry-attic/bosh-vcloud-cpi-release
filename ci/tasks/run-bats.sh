#!/usr/bin/env bash

set -e

source bosh-cpi-release/ci/tasks/utils.sh

check_param base_os
check_param BAT_NETWORKING
check_param BAT_DIRECTOR
check_param BAT_VCAP_PASSWORD

print_git_state bosh-cpi-release

export BAT_INFRASTRUCTURE=vcloud
cpi_release_name=bosh-${BAT_INFRASTRUCTURE}-cpi
export BAT_DNS_HOST=$BAT_DIRECTOR
export BAT_STEMCELL="${PWD}/stemcell/stemcell.tgz"
export BAT_DEPLOYMENT_SPEC="${PWD}/bosh-concourse-ci/pipelines/${cpi_release_name}/${base_os}-${BAT_NETWORKING}-bats-config.yml"

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

echo "using bosh CLI version..."
bosh version

ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa

bosh -n target $BAT_DIRECTOR

sed -i.bak s/"uuid: replace-me"/"uuid: $(bosh status --uuid)"/ $BAT_DEPLOYMENT_SPEC

cd bats
bundle install
bundle exec rspec spec
