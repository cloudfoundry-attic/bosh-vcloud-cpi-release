require "spec_helper"

module VCloudCloud
  module Steps
    describe PowerOff do
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg}
        client
      end

      let(:vm) do
        vm = double("vm")
        vm.stub(:power_off_link) { poweroff_link }
        vm.stub(:name) { "name" }
        vm
      end

      let(:poweroff_link) { "poweroff_link" }

      describe ".perform" do
        it "performs poweroff" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          }
          state = { vm: vm }
          client.should_receive(:invoke_and_wait).with(
            :post, poweroff_link
          )

          described_class.new(state, client).perform(:vm)
        end

        it "return when vm is already poweroff" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
          }
          state = { vm: vm }

          described_class.new(state, client).perform(:vm)
        end

        it "should not discard suspend state" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          }
          state = { vm: vm }
          client.should_receive(:invoke_and_wait).ordered.with(
            :post, poweroff_link
          )

          described_class.new(state, client).perform(:vm)
        end

        it "discards suspend state when required" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          }
          discard_state_link = "discard_state_link"
          vm.should_receive(:discard_state) { discard_state_link }
          state = { vm: vm }
          client.should_receive(:invoke_and_wait).ordered.with(
            :post, discard_state_link
          )
          client.should_receive(:invoke_and_wait).ordered.with(
            :post, poweroff_link
          )

          described_class.new(state, client).perform(:vm, true)
        end
      end
    end
  end
end
