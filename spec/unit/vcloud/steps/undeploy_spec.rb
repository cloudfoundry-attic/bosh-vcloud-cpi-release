require "spec_helper"

module VCloudCloud
  module Steps
    describe Undeploy do
      let(:client) do
        client = double("vcloud client")
        client.stub(:reload) { vm }
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.should_receive(:invoke_and_wait).with(
          :post, undeploy_link, anything)
        client
      end

      let(:vm) do
        vm = double("vm entity")
        vm.stub("[]").with("deployed") { 'true' }
        vm.should_receive(:undeploy_link) { undeploy_link }
        vm
      end

      let(:undeploy_link) { "undeploy_link" }

      it "Undeploy a vm" do
        Transaction.perform("undeploy", client) do |s|
          s.state[:vm] = vm
          s.next described_class, :vm
        end
      end
    end
  end
end
