require 'spec_helper'

describe VCloudCloud::Cloud do
  before(:all) do
    @host          = ENV['BOSH_VCLOUD_CPI_URL']     || raise("Missing BOSH_VCLOUD_CPI_URL")
    @user          = ENV['BOSH_VCLOUD_CPI_USER']     || raise("Missing BOSH_VCLOUD_CPI_USER")
    @password      = ENV['BOSH_VCLOUD_CPI_PASSWORD'] || raise("Missing BOSH_VCLOUD_CPI_PASSWORD")
    @vlan          = ENV['BOSH_VCLOUD_CPI_NET_ID']         || raise("Missing BOSH_VCLOUD_CPI_NET_ID")
    @stemcell_path = ENV['BOSH_VCLOUD_CPI_STEMCELL']     || raise("Missing BOSH_VCLOUD_CPI_STEMCELL")
    @org           = ENV['BOSH_VCLOUD_CPI_ORG']     || raise("Missing BOSH_VCLOUD_CPI_ORG")
    @vdc           = ENV['BOSH_VCLOUD_CPI_VDC']     || raise("Missing BOSH_VCLOUD_CPI_VDC")
    @vapp_catalog  = ENV['BOSH_VCLOUD_CPI_VAPP_CATALOG'] || raise("Missing BOSH_VCLOUD_CPI_VAPP_CATALOG")
    @vapp_name     = ENV['BOSH_VCLOUD_CPI_VAPP_NAME'] || raise("Missing BOSH_VCLOUD_CPI_VAPP_NAME")
    @media_catalog = ENV['BOSH_VCLOUD_CPI_MEDIA_CATALOG']         || raise("Missing BOSH_VCLOUD_CPI_MEDIA_CATALOG")
    @media_storage_prof  = ENV['BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE']     || raise("Missing BOSH_VCLOUD_CPI_MEDIA_STORAGE_PROFILE")
    @vapp_storage_prof  = ENV['BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE']     || raise("Missing BOSH_VCLOUD_CPI_VAPP_STORAGE_PROFILE")
    @metadata_key  = ENV['BOSH_VCLOUD_CPI_VM_METADATA_KEY']     || raise("Missing BOSH_VCLOUD_CPI_VM_METADATA_KEY")
    @target_ip1     = ENV['BOSH_VCLOUD_CPI_IP']     || raise("Missing BOSH_VCLOUD_CPI_IP")
    @target_ip2     = ENV['BOSH_VCLOUD_CPI_IP2']     || raise("Missing BOSH_VCLOUD_CPI_IP2")
    @target_ips     = [@target_ip1, @target_ip2]
    @netmask       = ENV['BOSH_VCLOUD_CPI_NETMASK'] || raise("Missing BOSH_VCLOUD_CPI_NETMASK")
    @dns           = ENV['BOSH_VCLOUD_CPI_DNS']         || raise("Missing BOSH_VCLOUD_CPI_DNS")
    @gateway       = ENV['BOSH_VCLOUD_CPI_GATEWAY']     || raise("Missing BOSH_VCLOUD_CPI_GATEWAY")

    # not required
    @ntp           = ENV['BOSH_VCLOUD_CPI_NTP_SERVER'] || '0.us.pool.ntp.org'
  end

  before(:all) do

    # randomize catalog names to ensure this CPI can create them on demand
    @vapp_catalog = "#{@vapp_catalog}_#{Process.pid}_#{rand(1000)}"
    @media_catalog = "#{@media_catalog}_#{Process.pid}_#{rand(1000)}"

    @cpis = []
    @network_specs = []

    @target_ips.each do |ip|
      @cpis << described_class.new(
        'agent' => {
          'ntp' => @ntp,
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
              'description' => 'BOSH on vCloudDirector',
            }
          }]
      )

      @network_specs << {
        "static" => {
          "ip" => ip,
          "netmask" => @netmask,
          "cloud_properties" => {"name" => @vlan},
          "default" => ["dns", "gateway"],
          "dns" => @dns,
          "gateway" => @gateway
        }
      }
    end

    @cpi = @cpis[0]
  end

  let(:resource_pool) {
    {
      'ram' => 1024,
      'disk' => 2048,
      'cpu' => 1,
    }
  }

  before(:all) do
    Dir.mktmpdir do |temp_dir|
      output = `tar -C #{temp_dir} -xzf #{@stemcell_path} 2>&1`
      raise "Corrupt image, tar exit status: #{$?.exitstatus} output: #{output}" if $?.exitstatus != 0
      @stemcell_id = @cpi.create_stemcell("#{temp_dir}/image", nil)
    end
  end

  after(:all) do
    @cpi.delete_stemcell(@stemcell_id) if @stemcell_id
    client = @cpi.client
    VCloudCloud::Test::delete_catalog_if_exists(client, @vapp_catalog)
    VCloudCloud::Test::delete_catalog_if_exists(client, @media_catalog)
  end

  before { @vm_ids = [] }

  after {
    @vm_ids.each do |vm_id|
      @cpi.delete_vm(vm_id) if vm_id
    end
  }

  before { @disk_ids = [] }
  after {
    @disk_ids.each do |disk_id|
      @cpi.delete_disk(disk_id) if disk_id
    end
  }

  def vm_lifecycle(cpi, network_spec, resource_pool, disk_locality)
    vm_id = cpi.create_vm(
      "#{@vapp_name}_#{Process.pid}_#{rand(1000)}",
      @stemcell_id,
      resource_pool,
      network_spec,
      disk_locality,
      {'vapp' => @vapp_name}
    )

    expect(vm_id).to_not be_nil
    @vm_ids << vm_id
    expect(cpi.has_vm?(vm_id)).to be true

    disk_id = cpi.create_disk(2048, {}, vm_id)
    expect(disk_id).to_not be_nil
    @disk_ids << disk_id

    cpi.attach_disk(vm_id, disk_id)
    cpi.detach_disk(vm_id, disk_id)
  end

  def vm_lifecycle_sequential(resource_pool, disk_locality)
    @target_ips.each_index do |i|
      vm_lifecycle(@cpis[i], @network_specs[i], resource_pool, disk_locality)
    end
  end

  def vm_lifecycle_concurrent(resource_pool, disk_locality)
    arr = []
    @target_ips.each_index do |i|
      arr << Thread.new { vm_lifecycle(@cpis[i], @network_specs[i], resource_pool, disk_locality) }
    end
    arr.each {|t| t.join }
  end

  describe 'vcloud' do
    context 'with existing disks' do
      before { @existing_volume_id = @cpi.create_disk(2048, {}) }
      after { @cpi.delete_disk(@existing_volume_id) if @existing_volume_id }

      it 'should exercise the vm lifecycle' do
        vm_lifecycle_sequential(resource_pool, [@existing_volume_id])
      end
    end

    context 'without existing disks' do
      it 'should exercise the vm lifecycle sequentially' do
        vm_lifecycle_sequential(resource_pool, [])
      end

      it 'should exercise the vm lifecycle concurrently' do
        vm_lifecycle_concurrent(resource_pool, [])
      end
    end
  end
end
