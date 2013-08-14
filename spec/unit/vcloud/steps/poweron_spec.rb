require "spec_helper"

module VCloudCloud
  module Steps
    describe PowerOn do
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg}
        client
      end

      let(:vm) do
        vm = double("vm")
        vm.stub(:power_on_link) { poweron_link }
        vm.stub(:name) { "name" }
        vm
      end

      let(:poweron_link) { "poweron_link" }
      describe ".perform" do
        it "performs poweron" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
          }
          state = { vm: vm }
          client.should_receive(:invoke_and_wait).with(
            :post, poweron_link
          )

          described_class.new(state, client).perform(:vm)
        end

        it "return when vm is already poweron" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          }
          state = { vm: vm }

          described_class.new(state, client).perform(:vm)
        end
      end
    end
  end
end
