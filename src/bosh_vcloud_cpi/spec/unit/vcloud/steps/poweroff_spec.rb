require "spec_helper"

module VCloudCloud
  module Steps
    describe PowerOff do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg}
        client
      end

      let(:vm) do
        vm = double("vm")
        allow(vm).to receive(:power_off_link) { poweroff_link }
        allow(vm).to receive(:name) { "name" }
        vm
      end

      let(:poweroff_link) { "poweroff_link" }

      describe ".perform" do
        it "performs poweroff" do
          allow(vm).to receive('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          }
          state = { vm: vm }
          expect(client).to receive(:invoke_and_wait).with(
            :post, poweroff_link
          )

          described_class.new(state, client).perform(:vm)
        end

        it "return when vm is already poweroff" do
          allow(vm).to receive('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
          }
          state = { vm: vm }

          described_class.new(state, client).perform(:vm)
        end

        it "should not discard suspend state" do
          allow(vm).to receive('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          }
          state = { vm: vm }
          expect(client).to receive(:invoke_and_wait).ordered.with(
            :post, poweroff_link
          )

          described_class.new(state, client).perform(:vm)
        end

        it "discards suspend state when required" do
          allow(vm).to receive('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          }
          discard_state_link = "discard_state_link"
          expect(vm).to receive(:discard_state) { discard_state_link }
          state = { vm: vm }
          expect(client).to receive(:invoke_and_wait).ordered.with(
            :post, discard_state_link
          )
          expect(client).to receive(:invoke_and_wait).ordered.with(
            :post, poweroff_link
          )

          described_class.new(state, client).perform(:vm, true)
        end
      end
    end
  end
end
