require 'spec_helper'

module VCloudCloud
  module Steps

    describe Instantiate do

      let(:template_id) {"tid"}
      let(:vapp_name) {"vapp_name"}
      let(:vapp_description) {"This is a vapp"}

      let(:disk) do
        disk = double("disk").as_null_object
        disk
      end

      let(:vm) do
        vm = double("vm").as_null_object
        vm
      end

      let(:catalog_item) do
        item = double("catalog item")
        allow(item).to receive(:entity) {template}
        item
      end

      let(:template) do
        template = double("vapp template")
        allow(template).to receive(:[]) {"value"}
        allow(template).to receive(:vms) {[vm]}
        template
      end

      let(:vapp) do
        vapp = double("vapp")
        allow(vapp).to receive(:name) {'testVapp'}
        vapp
      end

      let(:vapp_name) { "vapp_name" }

      let(:instantiate_vapp_template_link_value) {"http://vdc/instantiate/vapp/template"}
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:resolve_entity) do |arg|
          catalog_item if arg == template_id
        end
        allow(client).to receive(:resolve_link) do |arg|
          arg
        end
        allow(client).to receive(:invoke) do |method,link,params|
          vapp if method == :post && link == instantiate_vapp_template_link_value
        end
        allow(client).to receive_message_chain(:vdc, :instantiate_vapp_template_link) {instantiate_vapp_template_link_value}
        allow(client).to receive(:wait_entity) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "creates the vapp" do
          # setup test data
          disk_locality = [nil, disk, disk]
          state = {}

          # configure mock expectations
          expect(client).to receive(:resolve_entity).once.ordered.with(template_id)
          expect(catalog_item).to receive(:entity).once.ordered
          expect(client).to receive(:resolve_link).once.ordered.with(template)
          expect(template).to receive(:vms).twice.ordered
          expect(client).to receive(:vdc).once.ordered
          expect(client).to receive(:invoke).once.ordered.with(:post, instantiate_vapp_template_link_value, kind_of(Hash))
          expect(client).to receive(:wait_entity).once.ordered.with(vapp)

          # run the test
          step = described_class.new state, client
          step.perform template_id, vapp_name, vapp_description, disk_locality, nil
          expect(state[:vapp]).to eql vapp
        end

        it "raises ObjectNotFoundException" do
          # setup test data
          tid = "test"
          disk_locality = []
          state = {}

          # config mock expectations
          expect(client).to receive(:resolve_entity).once.ordered.with(tid)

          # run the test
          step = described_class.new state, client
          expect{step.perform tid, vapp_name, vapp_description, disk_locality, nil}.to raise_exception ObjectNotFoundError
          expect(state).to be {}
        end
      end

      describe ".rollback" do
        it "does nothing" do
          # setup test data
          state = {}

          # configure mock expectations
          expect(vapp).to_not receive(:remove_link)
          expect(client).to_not receive(:invoke_and_wait)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "invokes the method" do
          #setup the test data
          state = {:instantiate_vapp_name => vapp_name}
          remove_link = "http://vapp/remove"

          # configure mock expectations
          expect(client).to receive(:flush_cache).once.ordered
          expect(client).to receive(:vapp_by_name).once.ordered.with(vapp_name).and_return(vapp)
          expect(vapp).to receive(:remove_link).once.ordered { remove_link }
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:instantiate_vapp_name)).to be false
        end
      end
    end

  end
end
