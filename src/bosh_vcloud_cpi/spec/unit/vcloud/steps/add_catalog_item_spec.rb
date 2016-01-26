require 'spec_helper'

module VCloudCloud
  module Steps

    describe AddCatalogItem do

      let(:catalog_item) do
        catalog_item = double("vcloud catalog item")
        catalog_item
      end

      let(:catalog_type) {"vcloud_type"}
      let(:catalog_add_item_link) {"add_item_link"}
      let(:catalog) do
        catalog = double("vcloud catalog")
        allow(catalog).to receive(:add_item_link) { catalog_add_item_link }
        catalog
      end

      let(:resource_name) {"vcloud resource name"}
      let(:resource_item) do
        res = double("vcloud resource").as_null_object
        allow(res).to receive(:name) { resource_name }
        res
      end

      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:catalog) do |param|
          catalog if param == catalog_type
        end
        allow(client).to receive(:invoke) do |method, link, params|
          catalog_item if :post == method && catalog_add_item_link == link
        end
        client
      end

      describe ".perform" do
        it "invokes the method" do
          # setup test data
          state = {}

          # configure mock expectations
          expect(client).to receive(:catalog).once.ordered.with(catalog_type)
          expect(resource_item).to receive(:name).twice.ordered
          expect(catalog).to receive(:add_item_link).once.ordered
          expect(client).to receive(:invoke).once.ordered.with(:post, catalog_add_item_link, kind_of(Hash))

          # run test
          described_class.new(state, client).perform catalog_type, resource_item
          expect(state[:catalog_item]).to be catalog_item
        end
      end

      describe ".rollback" do
        it 'does nothing' do
          # setup test data
          state = {}

          # configure mock expectations
          expect(client).to_not receive(:invoke)

          # run test
          step = described_class.new state, client
          expect { step.rollback }.to_not raise_error
        end

        it "invokes the method" do
          #setup the test data
          state = {:catalog_item => catalog_item}

          # configure mock expectations
          expect(client).to receive(:invoke).once.ordered.with(:delete, catalog_item)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:catalog_item)).to be false
        end
      end
    end

  end
end
