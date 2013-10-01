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
        catalog.stub(:add_item_link) { catalog_add_item_link }
        catalog
      end

      let(:resource_name) {"vcloud resource name"}
      let(:resource_item) do
        res = double("vcloud resource").as_null_object
        res.stub(:name) { resource_name }
        res
      end

      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:catalog) do |param|
          catalog if param == catalog_type
        end
        client.stub(:invoke) do |method, link, params|
          catalog_item if :post == method && catalog_add_item_link == link
        end
        client
      end

      describe ".perform" do
        it "invokes the method" do
          # setup test data
          state = {}

          # configure mock expectations
          client.should_receive(:catalog).once.ordered.with(catalog_type)
          resource_item.should_receive(:name).twice.ordered
          catalog.should_receive(:add_item_link).once.ordered
          client.should_receive(:invoke).once.ordered.with(:post, catalog_add_item_link, kind_of(Hash))

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
          client.should_not_receive(:invoke)

          # run test
          step = described_class.new state, client
          expect { step.rollback }.to_not raise_error
        end

        it "invokes the method" do
          #setup the test data
          state = {:catalog_item => catalog_item}

          # configure mock expectations
          client.should_receive(:invoke).once.ordered.with(:delete, catalog_item)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:catalog_item)).to be_false
        end
      end
    end

  end
end
