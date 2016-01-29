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

  let(:vm_env) {
    {'vapp' => @vapp_name}
  }

  let(:client) {
    @cpi.client
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

  def random_vm_name
    "#{@vapp_name}_intergration_#{Process.pid}_#{rand(1000)}"
  end

  def vm_number_by_vappname (name)
    vapp_name = name
    client.flush_cache  # flush cached vdc which contains vapp list
    vapp = client.vapp_by_name vapp_name
    expect(vapp.name).to eq vapp_name
    vapp.vms.size
  end

  def expect_vapp_not_exist (name)
    vapp_name = name
    client.flush_cache  # flush cached vdc which contains vapp list
    expect { client.vapp_by_name vapp_name }.to raise_error VCloudCloud::ObjectNotFoundError
  end

  context "when create stemcell" do

    before do
      @retried_stemcell_id = nil
    end

    after do
      @cpi.delete_stemcell(@retried_stemcell_id) if @retried_stemcell_id
    end

    it "should retry if get Timeout::Error while uploading files" do
      should_timeout = true
      original_upload = VCloudCloud::FileUploader.method(:upload)
      allow_any_instance_of(VCloudCloud::FileUploader).to receive(:upload) do |*args, &block|
        if should_timeout
          should_timeout = false
          raise Timeout::Error
        else
          original_upload(*args, &block)
        end
      end

      expect {
        Dir.mktmpdir do |temp_dir|
          output = `tar -C #{temp_dir} -xzf #{@stemcell_path} 2>&1`
          raise "Corrupt image, tar exit status: #{$?.exitstatus} output: #{output}" if $?.exitstatus != 0
          @retried_stemcell_id = @cpi.create_stemcell("#{temp_dir}/image", nil)
        end
      }.to_not raise_error

      expect(@retried_stemcell_id).not_to eql(nil)

      # create a vm to ensure that the stemcell is valid
      vm_id = @cpi.create_vm random_vm_name, @retried_stemcell_id, resource_pool, @network_specs[0], [], vm_env
      expect(vm_id).to_not be_nil
      @vm_ids << vm_id
      has_vm = @cpi.has_vm? vm_id
      expect(has_vm).to be true

      expect { @cpi.delete_stemcell(@retried_stemcell_id) }.to_not raise_error
    end
  end

  context "when there is no error in create_vm" do
    it 'should create vm and reconfigure network' do
      vm_id = @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[0], [], vm_env
      expect(vm_id).to_not be_nil
      @vm_ids << vm_id
      has_vm = @cpi.has_vm? vm_id
      expect(has_vm).to be true

      expect {@cpi.configure_networks vm_id, @network_specs[1]}.to raise_error Bosh::Clouds::NotSupported
      disk_id = @cpi.create_disk(2048, {}, vm_id)
      expect(disk_id).to_not be_nil
      @disk_ids << disk_id

      @cpi.attach_disk vm_id, disk_id
      @cpi.detach_disk vm_id, disk_id

      @cpi.reboot_vm vm_id
    end
  end

  context "when received exception during create_vm" do

    before do
      allow(Bosh::Retryable).to receive(:new).and_return(retryable)
      allow(retryable).to receive(:retryer).and_yield(0, :error)
    end

    let(:retryable) { double('Bosh::Retryable') }

    context "when target vapp does not exist" do

      it 'should clean up the media when create_vm fail to PowerOn' do
        exceptionMsg = 'PowerOn Failed!'
        allow_any_instance_of(VCloudCloud::Steps::PowerOn).to receive(:perform).and_raise(exceptionMsg)
        begin
          @cpi.create_vm random_vm_name, @stemcell_id, resource_pool, @network_specs[0], [], vm_env
          fail 'create_vm should fail'
        rescue => ex
          expect(ex.to_s).to match(Regexp.new(exceptionMsg))
        end

        # Delete will raise error and fail the test if media leaks in the media_catalog
        expect {
          client = @cpi.client
          VCloudCloud::Test::delete_catalog_if_exists(client, @media_catalog)
        }.to_not raise_error
      end
    end
  end
end
