HOW TO PREPARE THIS FOLDER

1. Under bosh source tree
    bundle exec rake release:create_dev_release

2. Under this folder
    cp -rf <bosh-src>/vendor/cache bosh-cli/vendor
    cp <bosh-src>/pkg/gems/{bosh_cli,bosh_common,blobstore_client}-*.gem to bosh-cli/vendor/cache/
    cp -rf <bosh-src>/release/src/ruby .


Now you can do
    bosh create release