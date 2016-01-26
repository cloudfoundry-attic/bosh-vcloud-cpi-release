require "spec_helper"

module VCloudCloud
  module Steps
    describe Recompose do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg}
        client
      end

      let(:recompose_link) { "recompose_link" }

      let(:vm) do
        vm = double("vm")
        allow(vm).to receive(:href) { "href" }
        allow(vm).to receive(:name) { "vm_name" }
        vm
      end

      let(:vapp) do
        vapp = double("vapp")
        allow(vapp).to receive(:name) { vapp_name }
        vapp
      end
      let(:vapp_name) { "vapp_name" }

      describe ".perform" do
        it "perform recompose" do
          state = { :vm => vm }
          expect(client).to receive(:invoke_and_wait).with(
            :post, recompose_link, anything
          )
          expect(vapp).to receive(:recompose_vapp_link) { recompose_link }
          described_class.new(state, client).perform(vapp.name, vapp, vm)
        end
      end

      describe ".rollback" do
        it "does nothing" do
          # setup test data
          state = {}

          # configure mock expectations
          expect(client).to_not receive(:reload).with(vm)
          expect(client).to_not receive(:invoke_and_wait)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "deletes the vm" do
          #setup the test data
          state = {:vm => vm, :recompose_vapp_name => vapp_name}
          remove_link = "http://vm/remove"
          entity = double("entity")

          # configure mock expectations
          expect(client).to receive(:flush_cache).once.ordered
          expect(client).to receive(:vapp_by_name).once.ordered.with(vapp_name).and_return(vapp)
          expect(vapp).to receive(:vms).and_return [vm]
          expect(vm).to receive(:remove_link).once { remove_link }
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:vm)).to be false
          expect(state.key?(:recompose_vapp_name)).to be false
        end
      end
    end
  end
end
