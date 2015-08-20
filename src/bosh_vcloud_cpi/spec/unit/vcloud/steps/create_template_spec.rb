require 'spec_helper'

module VCloudCloud
  module Steps
    describe CreateTemplate do
      let(:template_name) { "my template" }
      let(:template) { double("vapp template") }
      let(:add_vapp_template_link) { double('XML Node', type: 'my custom type', content: 'http://example.com/catalog/upload/endpoint') }
      let(:catalog) { double(VCloudSdk::Xml::Catalog, add_vapp_template_link: add_vapp_template_link) }
      let(:client) do
        client = double(VCloudCloud::VCloudClient,
          catalog: catalog,
          logger: Bosh::Clouds::Config.logger
        )
        client.stub(:reload) { |arg| arg }
        client
      end

      describe ".perform" do
        it "creates a vapp template" do
          state = {}
          catalog_type = :catalog_type_name
          catalog_item = double(VCloudSdk::Xml::CatalogItem, entity: double('my_entity', href: 'http://example.com/catalog_item'))
          expected_params = VCloudSdk::Xml::WrapperFactory.create_instance 'UploadVAppTemplateParams'
          expected_params.name = template_name

          client.should_receive(:invoke).with(
            :post,
            add_vapp_template_link,
            {payload: expected_params, headers: {:content_type => 'my custom type'}}
          ).and_return(catalog_item)

          client.should_receive(:invoke).with(:get, 'http://example.com/catalog_item').and_return(template)

          step = described_class.new state, client
          expect {
            step.perform template_name, catalog_type
          }.to change { state }.from({}).to({
            catalog_item: catalog_item,
            vapp_template: template
          })
        end
      end

      describe ".rollback" do
        it "does nothing" do
          # setup test data
          state = {}

          # configure mock expectations
          template.should_not_receive(:cancel_link)
          template.should_not_receive(:remove_link)
          client.should_not_receive(:invoke)
          client.should_not_receive(:reload)
          client.should_not_receive(:invoke_and_wait)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "cancels and removes template" do
          # setup test data
          cancel_link = "http://vapp/cancel"
          remove_link = "http://vapp/remove"
          state = {:vapp_template => template}

          # configure mock expectations
          template.should_receive(:cancel_link).twice.ordered {cancel_link}
          client.should_receive(:invoke).once.ordered.with(:post, cancel_link)
          client.should_receive(:reload).once.ordered.with(template)
          template.should_receive(:remove_link).twice.ordered {remove_link}
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "removes template" do
          # setup test data
          remove_link = "http://vapp/remove"
          state = {:vapp_template => template}

          # configure mock expectations
          template.should_receive(:cancel_link).once.ordered {nil}
          client.should_not_receive(:invoke)
          client.should_not_receive(:reload)
          template.should_receive(:remove_link).twice.ordered {remove_link}
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "cancels template" do
          # setup test data
          cancel_link = "http://vapp/cancel"
          state = {:vapp_template => template}

          # configure mock expectations
          template.should_receive(:cancel_link).twice.ordered {cancel_link}
          client.should_receive(:invoke).once.ordered.with(:post, cancel_link)
          client.should_receive(:reload).once.ordered.with(template)
          template.should_receive(:remove_link).once.ordered
          client.should_not_receive(:invoke_and_wait)

          # run test
          step = described_class.new state, client
          step.rollback
        end
      end
    end

  end
end
