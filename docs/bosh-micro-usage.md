## Experimental `bosh-micro` usage

> !!! [bosh-micro cli](github.com/cloudfoundry/bosh-micro-cli) is still in active pre-release development !!!

To start experimenting with bosh-vcloud-cpi release and the new bosh-micro cli:

1. Create a deployment directory

    ```
    mkdir my-micro
    ```

1. Create a deployment manifest (ex: `manifest.yml`) inside the deployment directory

    Example deployment manifest:

    ```
    ---
    name: bosh-vcloud
    
    networks:
    - name: default
      type: manual
      ip: 192.168.112.140
      netmask: 255.255.255.0
      gateway: 192.168.112.1
      dns: ["8.8.8.8"]
      cloud_properties:
        name: VDC-BOSH
    
    resources:
      persistent_disk: 4096,
      cloud_properties:
        ram: 2048
        disk: 8192
        cpu: 1
    
    disk_pools:
    - name: ssd-disk-pool
      disk_size: 2048
    
    resource_pools:
    - name: default
      network: default
      cloud_properties:
        ram: 512
        disk: 2048
        cpu: 1
    
    env:
      vapp: bosh-acceptance-vapp
    
    vcloud_config: &vcloud
      url: https://p3v13-vcd.vchs.vmware.com
      user: ${VCLOUD_API_USER}
      password: ${VCLOUD_API_PASSWORD}
      entities:
        organization: ${VCLOUD_VDC_ORG}
        virtual_datacenter: ${VCLOUD_VDC}
        vapp_catalog: micro-bosh-catalog
        media_catalog: micro-bosh-catalog
        media_storage_profile: "*"
        vm_metadata_key: micro-bosh-meta
        description: MicroBosh on vCloudDirector
        control:
          wait_max: 900
    
    cloud_provider:
      mbus: https://${AGENT_USER}:${AGENT_PASSWORD}@192.168.112.140:6868
      properties:
        blobstore:
          provider: local
          path: /var/vcap/micro_bosh/data/cache
        agent:
          mbus: https://${AGENT_USER}:${AGENT_PASSWORD}@0.0.0.0:6868
          ntp: ["us.pool.ntp.org", "time1.google.com"]
        vcd: *vcloud
        log_file: ${CPI_LOG_PATH:-~/vcloud_cpi.log}
    
    jobs:
    - name: bosh
      instances: 1
      templates:
      - name: nats
      - name: redis
      - name: postgres
      - name: powerdns
      - name: blobstore
      - name: director
      - name: health_monitor
      - name: registry
      - name: bosh_vcloud_cpi
      networks:
      - name: default
        static_ips:
        - 192.168.112.140
      persistent_disk_pool: ssd-disk-pool
      properties:
        vcd: *vcloud
        registry:
          address: 192.168.112.140
          http:
            user: ${REGISTRY_USER}
            password: ${REGISTRY_PASSWORD}
            port: 25777
          db:
            user: ${POSTGRES_USER}
            password: ${POSTGRES_PASSWORD}
            host: 127.0.0.1
            database: bosh
            port: 5432
            adapter: postgres
        nats:
          user: ${NATS_USER}
          password: ${NATS_PASSWORD}
          auth_timeout: 3
          address: 127.0.0.1
        redis:
          address: 127.0.0.1
          password: ${REDIS_PASSWORD}
          port: 25255
        postgres:
          user: ${POSTGRES_USER}
          password: ${POSTGRES_PASSWORD}
          host: 127.0.0.1
          database: bosh
          port: 5432
        blobstore:
          address: 127.0.0.1
          director:
            user: ${DIRECTOR_USER}
            password: ${DIRECTOR_PASSWORD}
          agent:
            user: ${AGENT_USER}
            password: ${AGENT_PASSWORD}
          provider: dav
        director:
          address: 127.0.0.1
          name: micro
          port: 25555
          db:
            user: ${POSTGRES_USER}
            password: ${POSTGRES_PASSWORD}
            host: 127.0.0.1
            database: bosh
            port: 5432
            adapter: postgres
          backend_port: 25556
        hm:
          http:
            user: ${HEALTH_MONITOR_USER}
            password: ${HEALTH_MONITOR_PASSWORD}
          director_account:
            user: ${DIRECTOR_USER}
            password: ${DIRECTOR_PASSWORD}
        dns:
          address: 192.168.112.140
          domain_name: microbosh
          db:
            user: ${POSTGRES_USER}
            password: ${POSTGRES_PASSWORD}
            host: 127.0.0.1
            database: bosh
            port: 5432
            adapter: postgres
        ntp: []
    ```

1. Set deployment

    ```
    bosh-micro deployment my-micro/manifest.yml
    ```

1. Kick off a deploy

    ```
    bosh-micro deploy \
        /path/to/bosh-stemcell-${STEMCELL_VERSION}-vcloud-esxi-ubuntu-trusty-go_agent.tgz \
        /path/to/bosh-vcloud-cpi-${CPI_VERSION}.tgz \
        /path/to/bosh-${BOSH_VERSION}.tgz
    ```
