require 'spec_helper'
require 'cloud/vcloud/steps/add_catalog'

describe VCloudCloud::Steps::AddCatalog do
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
    @logger = Logger.new ENV['LOGGER']
    @logger.formatter = ThreadFormatter.new

    @client = VCloudCloud::VCloudClient.new(
      {
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
      },
      @logger # TODO logger
    )

  end

  let(:add_catalog_step) { described_class.new({}, @client) }
  let(:catalog_name) { "a_bosh_test_catalog_#{Process.pid}_#{rand(1000)}" }

  after do
    VCloudCloud::Test::delete_catalog_if_exists(@client, catalog_name)
  end

  context 'when the catalog does not yet exist' do
    it 'creates the catalog' do
      result = add_catalog_step.perform(catalog_name)
      expect(result.name).to eq(catalog_name)

      @client.flush_cache

      catalog = @client.org.catalog_link(catalog_name)
      expect(catalog.name).to eq(catalog_name)
      expect(catalog.type).to eq(VCloudSdk::Xml::MEDIA_TYPE[:CATALOG])
    end

    it 'rollback does nothing' do
      result = add_catalog_step.perform(catalog_name)
      add_catalog_step.rollback

      @client.flush_cache

      catalog = @client.org.catalog_link(catalog_name)
      expect(catalog.name).to eq(catalog_name)
      expect(catalog.type).to eq(VCloudSdk::Xml::MEDIA_TYPE[:CATALOG])
    end
  end

  context 'when the catalog exists' do
    it 'should return successfully from perform' do
      result = add_catalog_step.perform(catalog_name)
      expect(result.name).to eq(catalog_name)

      @client.flush_cache

      result2 = add_catalog_step.perform(catalog_name)
      expect(result2.name).to eq(catalog_name)

      @client.flush_cache

      catalog = @client.org.catalog_link(catalog_name)
      expect(catalog.name).to eq(catalog_name)
      expect(catalog.type).to eq(VCloudSdk::Xml::MEDIA_TYPE[:CATALOG])
    end

    it 'should do nothing in rollback' do
      result = add_catalog_step.perform(catalog_name)
      expect(result.name).to eq(catalog_name)

      # in a different step instance, try to create a catalog with the same name
      add_catalog_step2 = described_class.new({}, @client)
      add_catalog_step2.perform(catalog_name)
      add_catalog_step2.rollback

      @client.flush_cache

      # the rollback above should have done nothing.. the catalog should still exist
      catalog = @client.org.catalog_link(catalog_name)
      expect(catalog.name).to eq(catalog_name)
      expect(catalog.type).to eq(VCloudSdk::Xml::MEDIA_TYPE[:CATALOG])
    end
  end
end
