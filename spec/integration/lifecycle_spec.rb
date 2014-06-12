require 'spec_helper'

describe VCloudCloud::Cloud do
  before(:all) do

=begin
    File.readlines("./spec/integration/env.txt").each do |line|
      values = line.split("=")
      ENV[values[0].strip] = values[1].strip
    end
=end

    @host          = ENV['BOSH_VCLOUD_CPI_URL']     || raise("Missing BOSH_VCLOUD_CPI_URL")
    @user          = ENV['BOSH_VCLOUD_CPI_USER']     || raise("Missing BOSH_VCLOUD_CPI_USER")
    @password      = ENV['BOSH_VCLOUD_CPI_PASSWORD'] || raise("Missing BOSH_VCLOUD_CPI_PASSWORD")
    @vlan          = ENV['BOSH_VCLOUD_CPI_NET_ID']         || raise("Missing BOSH_VCLOUD_CPI_NET_ID")
    @stemcell_path = ENV['BOSH_VCLOUD_CPI_STEMCELL']     || raise("Missing BOSH_VCLOUD_STEMCELL")
    @org           = ENV['BOSH_VCLOUD_CPI_ORG']     || raise("Missing BOSH_VCLOUD_CPI_ORG")
    @vdc           = ENV['BOSH_VCLOUD_CPI_VDC']     || raise("Missing BOSH_VCLOUD_CPI_VDC")
    @vapp_catalog  = ENV['BOSH_VCLOUD_CPI_VAPP_CATALOG'] || raise("Missing BOSH_VCLOUD_CPI_VAPP_CATALOG")
    @media_catalog = ENV['BOSH_VCLOUD_CPI_MEDIA_CATALOG']         || raise("Missing BOSH_VCLOUD_CPI_MEDIA_CATALOG")
    @media_storage_prof  = ENV['BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE']     || raise("Missing BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE")
    @vapp_storage_prof  = ENV['BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE']     || raise("Missing BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE")
    @metadata_key  = ENV['BOSH_VCLOUD_CPI_VM_METADATA_KEY']     || raise("Missing BOSH_VCLOUD_CPI_VM_METADATA_KEY")
    @target_ip     = ENV['BOSH_VCLOUD_CPI_IP']     || raise("Missing BOSH_VCLOUD_CPI_IP")
    @target_ip2     = ENV['BOSH_VCLOUD_CPI_IP2']     || raise("Missing BOSH_VCLOUD_CPI_IP2")
    @netmask       = ENV['BOSH_VCLOUD_CPI_NETMASK'] || raise("Missing BOSH_VCLOUD_CPI_NETMASK")
    @dns           = ENV['BOSH_VCLOUD_CPI_DNS']         || raise("Missing BOSH_VCLOUD_CPI_DNS")
    @gateway       = ENV['BOSH_VCLOUD_CPI_GATEWAY']     || raise("Missing BOSH_VCLOUD_CPI_GATEWAY")
  end

  before(:all) do
    @cpi = described_class.new(
      'agent' => {
        'ntp' => ENV['BOSH_VCLOUD_CPI_NTP_SERVER'],
      },
      'vcds' => [{
        'url' => @host,
        'user' => @user,
        'password' => @password,
        'entities' => {
          'organization' => @org,
          'virtual_datacenter' => @vdc,
          'vapp_catalog' => @vapp_catalog,
          'media_catalog' => @media_catalog,
          'media_storage_profile' => @media_storage_prof,
          'vapp_storage_profile' => @vapp_storage_prof,
          'vm_metadata_key' => @metadata_key,
          'description' => 'MicroBosh on vCloudDirector',
        }
      }]
    )

  end

  let(:cpi) { @cpi }

  before(:all) do
    Dir.mktmpdir do |temp_dir|
      output = `tar -C #{temp_dir} -xzf #{@stemcell_path} 2>&1`
      raise "Corrupt image, tar exit status: #{$?.exitstatus} output: #{output}" if $?.exitstatus != 0
      @stemcell_id = @cpi.create_stemcell("#{temp_dir}/image", nil)
    end
  end

  after(:all) { cpi.delete_stemcell(@stemcell_id) if @stemcell_id }

  before {
    @vm_id = nil
    @vm_id2 = nil
  }

  after {
    cpi.delete_vm(@vm_id) if @vm_id
    cpi.delete_vm(@vm_id2) if @vm_id2
  }


  before { @disk_id, @disk_id2 = nil, nil }
  after {
    cpi.delete_disk(@disk_id) if @disk_id
    cpi.delete_disk(@disk_id2) if @disk_id2
  }

  def vm_lifecycle(network_spec, disk_locality)
    resource_pool = {
      'ram' => 1024,
      'disk' => 2048,
      'cpu' => 1,
    }

    @vm_id = cpi.create_vm(
      'agent1-007',
      @stemcell_id,
      resource_pool,
      network_spec,
      disk_locality,
      {'key' => 'value'}
    )

    @vm_id.should_not be_nil
    cpi.has_vm?(@vm_id).should be(true)

    @disk_id = cpi.create_disk(2048, @vm_id)
    @disk_id.should_not be_nil

    cpi.attach_disk(@vm_id, @disk_id)

    cpi.detach_disk(@vm_id, @disk_id)

    #now use the same vapp name and different vm name to create vm again

    network_spec["static"]["ip"] = @target_ip2
    @vm_id2 = cpi.create_vm(
        'agent1-008',
        @stemcell_id,
        resource_pool,
        network_spec,
        disk_locality,
        {'key' => 'value', 'vapp' => 'agent1-007'}
    )

    cpi.has_vm?(@vm_id2).should be(true)

    @disk_id2 = cpi.create_disk(2048, @vm_id2)
    @disk_id2.should_not be_nil

    cpi.attach_disk(@vm_id2, @disk_id2)

    cpi.detach_disk(@vm_id2, @disk_id2)

  end

  describe 'vcloud' do
    let(:network_spec) do
      {
        "static" => {
          "ip" => @target_ip,
          "netmask" => @netmask,
          "cloud_properties" => {"name" => @vlan},
          "default" => ["dns", "gateway"],
          "dns" => @dns,
          "gateway" => @gateway
        }
      }
    end

    context 'without existing disks' do
      it 'should exercise the vm lifecycle' do
        vm_lifecycle(network_spec, [])
      end
    end

    context 'with existing disks' do
      before { @existing_volume_id = cpi.create_disk(2048) }
      after { cpi.delete_disk(@existing_volume_id) if @existing_volume_id }

      it 'should exercise the vm lifecycle' do
        vm_lifecycle(network_spec, [@existing_volume_id])
      end
    end
  end
end
