# BOSH VCloud Cloud Provider Interface
Copyright (c) VMware, Inc.

## Introduction

A BOSH CPI implementation for a vCloud Director backed infrastructure cloud.

Use the vSphere MicroBosh and BOSH stemcells when targetting vCloud Director.

In order to target a vCloud Director instance, MicroBosh must be set to use
the vCloud plugin configuration as shown below:

    ---
	plugin: vcloud
    vcds
	  - url:  <VCD url> (e.g. http://1.2.3.4)
	    user: <VCD user> (e.g. orgadmin)      
        password: <>
	    entities:
		    organization: <Organization name>
		    virtual_datacenter: <VDC name>
		    vapp_catalog: <Organization catalog name>
		    media_catalog: <Organization catalog name>
		    vm_metadata_key: cf-agent-env
		    description: <Text associated with Cloud Foundry VMs>
   

Note that vCloud Director version 5.1 or newer is required.


## Example

This is a sample of how vCloud Director specific properties are used in a BOSH deployment manifest:

    ---
    name: sample
    director_uuid: 38ce80c3-e9e9-4aac-ba61-97c676631b91

    ...
	
	networks:
	- name: default # An internal name for the network in your manifest file
	  subnets:
	  - reserved:
	    - 10.146.21.129 - 10.146.21.150
	    static:
	    - 10.146.21.151 - 10.146.21.189
	    range: 10.146.21.128/25
	    gateway: 10.146.21.253
	    dns:
	    - 10.132.71.1
	    cloud_properties:
	      name: "tempest_vdc_network"

    ...

    properties:
	  vcd:
	    url: https://10.146.21.135
	    user: dev_mgr
	    password: vmware
	    entities:
	      organization: dev
	      virtual_datacenter: tempest
	      vapp_catalog: cloudfoundry
	      media_catalog: cloudfoundry 
	      media_storage_profile: *
	      vm_metadata_key: cf-agent-env
	      description: Bosh on vCloudDirector
