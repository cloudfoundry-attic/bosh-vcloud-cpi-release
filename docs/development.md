## Development

### Updating vendored dependencies

#### Install the Bundler Ruby gem

```
gem install bundler
```

#### Execute the vendoring script

```
cd src/bosh_vcloud_cpi
./vendor_gems
```

### Creating a new BOSH release

#### Development

1. Make local changes to the release

2. Create a dev release

    (--force is required if there are local changes not committed to git)

    ```
    bosh create release --force --with-tarball
    ```

### Final

1. Configure the blobstore secrets in `config/private.yml`.

2. Create a final release

    (--final will upload the package/job blobs to the blobstore)

    ```
    bosh create release --final --with-tarball
    ```

3. Tag the final release (optional)

4. Push changes to github

### Creating a tarball of an existing BOSH release

Create a release tarball using an existing manifest

```
bosh create release ./releases/bosh-vcloud-cpi/bosh-vcloud-cpi-<version>.yml --with-tarball
```
