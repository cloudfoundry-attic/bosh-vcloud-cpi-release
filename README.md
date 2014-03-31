# BOSH VCloud Cloud Provider Interface
Copyright (c) VMware, Inc.

## Introduction

It's a BOSH CPI implementation for a vCloud Director backed infrastructure cloud. 
In order to target a vCloud Director instance, MicroBosh must be set to use
the vCloud plugin configuration as shown below:

    ---
	plugin: vcloud
    vcds
	  - url:   
	    user:      
        password: 
	    entities:
		  organization: 
		  virtual_datacenter: 
		  vapp_catalog: 
		  media_catalog:
		  media_storage_profile:
          vm_metadata_key:
		  description:
          control: #optional parameters
            wait_max: #optional parameters     

Note that vCloud Director version 5.1 or newer is required.

## Parameters

This section explains which parameters are supported in vCloud BOSH CPI.

### vCloud related

* `url` (required)
  The endpoint of the target vCloud Director 
* `user` (required)
  The user name of the target vCloud Director 
* `password` (required)
  The password of the target vCloud Director
* `organization` (required)
  The organization name 
* `virtual_datacenter` (required)
  The virtual data center name
* `vapp_catalog` (required)
  The name of the calalog for vapp template
* `media_catalog` (required)
  The name of the calalog for media files
* `media_storage_profile` (required)
  The storage profile to use. You can put * here to match all the storage profiles.  
* `vm_metadata_key` (required)
  The key name of VM metadata
* `description` (required)
  Text associated with the VMs
* `Control` (optional)
  All the following control parameters are optional  
* `wait_max` (optional)
  Maximum wait seconds for a single CPI task
* `wait_delay` (optional)
  Delay in seconds for pooling next CPI task status
* `cookie_timeout` (optional)
  The cookie timeout in seconds
* `retry_max` (optional)
  Maximum retry times
* `retry_delay` (optional)
  The delay of first retry, the next is *2


### Network related

The network name should be specified under `cloud_properties` in the `networks` section of a BOSH deployment manifest. It should be the 'Org VDC Network' you plan to use for deployment. 


## Example

This is a sample of how vCloud Director specific properties are used in a  BOSH deployment manifest:

    ---
	networks:
	- name: default 
	  subnets:
	    - reserved:
	    - 192.168.21.129 - 192.168.21.150
	    static:
	    - 192.168.21.151 - 192.168.21.189
	    range: 192.168.21.128/25
	    gateway: 192.168.21.253
	    dns:
	    - 192.168.71.1
	    cloud_properties:
	      name: "tempest_vdc_network"

    ...

    properties:
	  vcd:
	    url: https://192.168.10.1
	    user: dev
	    password: pwd
	    entities:
	      organization: dev
	      virtual_datacenter: vdc
	      vapp_catalog: cloudfoundry
	      media_catalog: cloudfoundry 
	      media_storage_profile: *
	      vm_metadata_key: cf-agent-env
	      description: Bosh on vCloudDirector
