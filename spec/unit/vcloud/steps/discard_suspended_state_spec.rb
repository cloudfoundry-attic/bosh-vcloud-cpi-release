require "spec_helper"

module VCloudCloud
  module Steps
    describe DiscardSuspendedState do
      let(:client) do
        client = double("client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg}
        client
      end

      let(:vm) do
        vm = double("vm")
        vm.stub(:name) { "vm_name" }
        vm
      end

      let(:discard_state_link) { "discard_state_link" }

      describe ".perform" do
        it "discards suspended state" do
          vm.should_receive("[]").with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          }
          vm.should_receive(:discard_state) { discard_state_link }
          client.should_receive(:invoke_and_wait).with(
            :post, discard_state_link
          )
          state = { vm: vm}

          described_class.new(state, client).perform :vm
        end

        it "should return when power state is not suspended" do
          vm.should_receive("[]").with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          }
          state = { vm: vm}

          described_class.new(state, client).perform :vm
        end
      end
    end
  end
end
