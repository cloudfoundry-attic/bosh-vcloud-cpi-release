## Experimental `bosh-micro` usage

> !!! [bosh-micro cli](github.com/cloudfoundry/bosh-micro-cli) is still in active pre-release development !!!

To start experimenting with bosh-vcloud-cpi release and the new bosh-micro cli:

1. Create a deployment directory

    ```
    mkdir my-micro
    ```

1. Create a deployment manifest inside the deployment directory

    Example deployment manifest:

    TODO: vCloud deployment manifest example

1. Set deployment

    ```
    bosh-micro deployment my-micro/manifest.yml
    ```

1. Kick off a deploy

    ```
    bosh-micro deploy /path/to/bosh-stemcell-<version>-vcloud-esxi-ubuntu-trusty-go_agent.tgz /path/to/bosh-vcloud-cpi-<version>.tgz /path/to/bosh-<version>.tgz
    ```
