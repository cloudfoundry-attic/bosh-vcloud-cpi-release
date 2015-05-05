# BOSH vCloud CPI Release

* Documentation: [bosh.io/docs](https://bosh.io/docs)
* IRC: [`#bosh` on freenode](https://webchat.freenode.net/?channels=bosh)
* Mailing list: [cf-bosh](https://lists.cloudfoundry.org/pipermail/cf-bosh)
* Roadmap: [Pivotal Tracker](https://www.pivotaltracker.com/n/projects/956238) (label:vcloud)

This is a BOSH release for the [vCloud CPI](https://github.com/vchs/bosh_vcloud_cpi/).

See [Initializing a BOSH environment on vCloud](https://bosh.io/docs/init-vcloud.html) for example usage.

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
