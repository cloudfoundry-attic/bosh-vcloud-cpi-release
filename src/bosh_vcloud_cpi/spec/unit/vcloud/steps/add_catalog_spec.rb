require 'spec_helper'

module VCloudCloud
  module Steps

    describe AddCatalog do


      let(:catalog) do
        catalog = double("vcloud catalog")
        allow(catalog).to receive(:name) {"a_bosh_fake_catalog"}
        catalog
      end

      let(:catalog_link) { VCloudSdk::Xml::Catalog.new(Nokogiri::XML('<Link rel="down" href="https://myvcloud/api/catalog/uuid" name="totally_existing_catalog" type="application/vnd.vmware.vcloud.catalog+xml"/>')) }
      let(:catalog_add_link) { VCloudSdk::Xml::AdminCatalog.new(Nokogiri::XML('<Link rel="add" href="https://myvcloud/api/admin/org/uuid/catalogs" type="application/vnd.vmware.admin.catalog+xml"/>')) }
      let(:org) do
        org = double("vcloud catalog")
        allow(org).to receive(:add_catalog_link) { catalog_add_link }
        allow(org).to receive(:catalog_link) { catalog_link }
        org
      end

      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:org) { org }
        allow(client).to receive(:invoke) do |method, link, params|
          catalog if :post == method && catalog_add_link == link
        end
        allow(client).to receive(:wait_entity) { catalog }
        allow(client).to receive(:flush_cache)
        allow(client).to receive(:resolve_link).with(catalog_link) { catalog }
        client
      end

      describe ".perform" do
        it 'can create a catalog' do
          expect(client).to receive(:invoke).once.ordered.with(:post, catalog_add_link, kind_of(Hash))
          expect(client).to receive(:wait_entity).with(catalog)

          described_class.new({}, client).perform catalog.name
        end

        it 'does not fail when the requested catalog already exists' do
          expect(client).to receive(:invoke).once.ordered.with(:post, catalog_add_link, kind_of(Hash)) { raise RestClient::BadRequest, '400' }
          expect(client).to receive(:flush_cache).once.ordered

          result = described_class.new({}, client).perform catalog.name
          expect(result).to_not be_nil
          expect(result.name).to eq catalog.name
        end

        it 'should fail when creating the folder gives an unexpected error' do
          allow(org).to receive(:catalog_link) { nil }

          expect(client).to receive(:invoke).once.ordered.with(:post, catalog_add_link, kind_of(Hash)) { raise RestClient::BadRequest, '400' }
          expect(client).to receive(:flush_cache).once.ordered

          expect { described_class.new({}, client).perform catalog.name }.to raise_error RestClient::BadRequest
        end

        it 'does not affect state' do
          state = {}

          expect(client).to receive(:invoke).once.ordered.with(:post, catalog_add_link, kind_of(Hash))
          expect(client).to receive(:wait_entity).with(catalog)

          described_class.new(state, client).perform catalog.name
          expect(state).to eq({})
        end
      end

      describe ".rollback" do
        it 'does nothing' do
          expect(client).to_not receive(:invoke)
          described_class.new({}, client).rollback
        end
      end
    end

  end
end
