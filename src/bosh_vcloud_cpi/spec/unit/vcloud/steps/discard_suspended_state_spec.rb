require "spec_helper"

module VCloudCloud
  module Steps
    describe DiscardSuspendedState do
      let(:client) do
        client = double("client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg}
        client
      end

      let(:vm) do
        vm = double("vm")
        allow(vm).to receive(:name) { "vm_name" }
        vm
      end

      let(:discard_state_link) { "discard_state_link" }

      describe ".perform" do
        it "discards suspended state" do
          expect(vm).to receive("[]").with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          }
          expect(vm).to receive(:discard_state) { discard_state_link }
          expect(client).to receive(:invoke_and_wait).with(
            :post, discard_state_link
          )
          state = { vm: vm}

          described_class.new(state, client).perform :vm
        end

        it "should return when power state is not suspended" do
          expect(vm).to receive("[]").with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          }
          state = { vm: vm}

          described_class.new(state, client).perform :vm
        end
      end
    end
  end
end
