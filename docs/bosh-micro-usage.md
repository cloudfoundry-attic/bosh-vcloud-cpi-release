## Experimental `bosh-micro` usage

> !!! [bosh-micro cli](github.com/cloudfoundry/bosh-micro-cli) is still in active pre-release development !!!

To start experimenting with bosh-vcloud-cpi release and the new bosh-micro cli:

1. Create a deployment directory

    ```
    mkdir my-micro
    ```

1. Create a deployment manifest (ex: `manifest.yml`) inside the deployment directory

    Example deployment manifest (using bash variables):

    ```yaml
    ---
    name: bosh

    networks:
    - name: default
      type: manual
      ip: 192.168.112.140
      netmask: 255.255.255.0
      gateway: 192.168.112.1
      dns: ["8.8.8.8"]
      cloud_properties:
        name: VDC-BOSH

    resource_pools:
    - name: default
      network: default
      cloud_properties:
        ram: 2048
        disk: 10_000
        cpu: 1

    disk_pools:
    - name: ssd-disk-pool
      disk_size: 10_000

    jobs:
    - name: bosh
      templates:
      - {name: nats, release: bosh}
      - {name: redis, release: bosh}
      - {name: postgres, release: bosh}
      - {name: blobstore, release: bosh}
      - {name: director, release: bosh}
      - {name: health_monitor, release: bosh}
      - {name: cpi, release: bosh-vcloud-cpi}

      instances: 1
      persistent_disk_pool: ssd-disk-pool

      networks:
      - name: default

      properties:
        nats:
          address: 127.0.0.1
          user: nats
          password: nats-password

        redis:
          listen_addresss: 127.0.0.1
          address: 127.0.0.1
          password: redis-password

        postgres: &db
          host: 127.0.0.1
          user: postgres
          password: postgres-password
          database: bosh
          adapter: postgres

        # Tells the Director/agents how to contact blobstore
        blobstore:
          address: 192.168.112.140
          port: 25250
          provider: dav
          director: {user: director, password: director-password}
          agent: {user: agent, password: agent-password}

        director:
          address: 127.0.0.1
          name: micro
          db: *db
          # Use external CPI
          cpi_job: cpi

        hm:
          http: {user: hm, password: hm-password}
          director_account: {user: admin, password: admin}

        vcd: &vcloud
          url: VCLOUD_URL
          user: VCLOUD_USER
          password: "VCLOUD_PASSWORD"
          entities:
            organization: VCLOUD_ORG
            virtual_datacenter: VCLOUD_VDC
            vapp_catalog: VCLOUD_VAPP_VATALOG
            media_catalog: VCLOUD_MEDIA_VATALOG
            media_storage_profile: "*"
            vm_metadata_key: micro-bosh-meta
            description: MicroBosh on vCloudDirector
            control:
              wait_max: 900

        # Tells agents how to contact nats
        agent: {mbus: "nats://nats:nats-password@192.168.112.140:4222"}

        ntp: &ntp
        - 0.north-america.pool.ntp.org
        - 1.north-america.pool.ntp.org
        - 2.north-america.pool.ntp.org
        - 3.north-america.pool.ntp.org

    cloud_provider:
      template: {name: cpi, release: bosh-vcloud-cpi}

      # Tells bosh-micro how to contact remote agent
      mbus: https://mbus-user:mbus-password@192.168.112.140:6868

      properties:
        vcd: *vcloud

        # Tells CPI how agent should listen for requests
        agent: {mbus: "https://mbus-user:mbus-password@0.0.0.0:6868"}

        blobstore:
          provider: local
          path: /var/vcap/micro_bosh/data/cache

        ntp: *ntp

    ```

1. Set deployment

    ```
    bosh-micro deployment my-micro/manifest.yml
    ```

1. Kick off a deploy

    ```
    bosh-micro deploy \
        /path/to/bosh-stemcell-${STEMCELL_VERSION}-vcloud-esxi-ubuntu-trusty-go_agent.tgz \
        /path/to/bosh-vcloud-cpi-${VCLOUD_CPI_VERSION}.tgz \
        /path/to/bosh-${BOSH_VERSION}.tgz
    ```
