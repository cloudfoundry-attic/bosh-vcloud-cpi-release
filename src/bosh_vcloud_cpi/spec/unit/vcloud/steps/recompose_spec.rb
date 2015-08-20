require "spec_helper"

module VCloudCloud
  module Steps
    describe Recompose do
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg}
        client
      end

      let(:recompose_link) { "recompose_link" }

      let(:vm) do
        vm = double("vm")
        vm.stub(:href) { "href" }
        vm.stub(:name) { "vm_name" }
        vm
      end

      let(:vapp) do
        vapp = double("vapp")
        vapp.stub(:name) { vapp_name }
        vapp
      end
      let(:vapp_name) { "vapp_name" }

      describe ".perform" do
        it "perform recompose" do
          state = { :vm => vm }
          client.should_receive(:invoke_and_wait).with(
            :post, recompose_link, anything
          )
          vapp.should_receive(:recompose_vapp_link) { recompose_link }
          described_class.new(state, client).perform(vapp.name, vapp, vm)
        end
      end

      describe ".rollback" do
        it "does nothing" do
          # setup test data
          state = {}

          # configure mock expectations
          client.should_not_receive(:reload).with(vm)
          client.should_not_receive(:invoke_and_wait)

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
          client.should_receive(:flush_cache).once.ordered
          client.should_receive(:vapp_by_name).once.ordered.with(vapp_name).and_return(vapp)
          vapp.should_receive(:vms).and_return [vm]
          vm.should_receive(:remove_link).once { remove_link }
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:vm)).to be_false
          expect(state.key?(:recompose_vapp_name)).to be_false
        end
      end
    end
  end
end
