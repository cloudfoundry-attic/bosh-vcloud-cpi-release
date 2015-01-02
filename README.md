# BOSH vCloud CPI Release

BOSH release for the external [vCloud CPI](https://github.com/vchs/bosh_vcloud_cpi/).

This release can be collocated with the BOSH release or used with new [bosh-micro cli](https://github.com/cloudfoundry/bosh-micro-cli).

## Experimental `bosh-micro` usage

See [bosh-micro usage doc](docs/bosh-micro-usage.md).

See [troubleshooting page](docs/troubleshooting.md) for common errors and resolutions.

## Development

See [development doc](docs/development.md).

## Active Ingedients

1. Jobs
  1. **cpi** - vcloud cpi wrapper script installed to `$BOSH_JOBS_DIR/cpi/bin/cpi`
1. Packages
  1. **ruby_vcloud_cpi** - installs yaml, ruby, and rubygems from tarballs in the blobstore
  1. **bosh_vcloud_cpi** - gem installs bosh_vcloud_cpi and its gem dependencies
1. Source 
  1. **bosh_vcloud_cpi** - bosh_vcloud_cpi gem and its gem dependencies
