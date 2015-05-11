require 'spec_helper'

module VCloudCloud
  module Steps

    describe AddCatalog do

      let(:catalog) do
        catalog = double("vcloud catalog")
        catalog.stub(:name) {"a_bosh_fake_catalog"}
        catalog
      end

      let(:catalog_add_link) { VCloudSdk::Xml::AdminCatalog.new(Nokogiri::XML('<Link rel="add" href="https://myvcloud/api/admin/org/uuid/catalogs" type="application/vnd.vmware.admin.catalog+xml"/>')) }
      let(:org) do
        org = double("vcloud catalog")
        org.stub(:add_catalog_link) { catalog_add_link }
        org.stub(:catalog_link) { VCloudSdk::Xml::Catalog.new(Nokogiri::XML('<Link rel="down" href="https://myvcloud/api/catalog/uuid" name="totally_existing_catalog" type="application/vnd.vmware.vcloud.catalog+xml"/>'))}
        org
      end

      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:org) {org}
        client.stub(:invoke) do |method, link, params|
          catalog if :post == method && catalog_add_link == link
        end
        client.stub(:wait_entity) {catalog}
        client.stub(:flush_cache)
        client
      end

      describe ".perform" do
        it 'can create a catalog' do
          # setup test data
          state = {}

          # configure mock expectations
          client.should_receive(:invoke).once.ordered.with(:post, catalog_add_link, kind_of(Hash))
          client.should_receive(:wait_entity).with(catalog)

          # run test
          described_class.new(state, client).perform catalog.name
          expect(state[:catalog]).to be catalog
        end
      end

      describe ".rollback" do
        it 'does not store anything in the state hash when the catalog already existed' do
          client.stub(:invoke) do |method, link, params|
            raise RestClient::BadRequest.new('400 Bad Request')
          end

          # run test
          state = {}
          step = described_class.new state, client
          expect(state.key?(:catalog)).to be_false
        end

        it 'does nothing when the state hash is empty' do
          # setup test data
          state = {}

          # configure mock expectations
          client.should_not_receive(:invoke)

          # run test
          step = described_class.new state, client
          expect { step.rollback }.to_not raise_error
        end

        it 'deletes a catalog that was created' do
          #setup the test data
          state = {:catalog => catalog}

          # configure mock expectations
          client.should_receive(:invoke).once.ordered.with(:delete, catalog)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:catalog)).to be_false
        end
      end
    end

  end
end
