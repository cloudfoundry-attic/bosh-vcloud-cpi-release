require "spec_helper"

module VCloudCloud
  module Steps
    describe Undeploy do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:reload) { vm }
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        expect(client).to receive(:invoke_and_wait).with(
          :post, undeploy_link, anything)
        client
      end

      let(:vm) do
        vm = double("vm entity")
        allow(vm).to receive("[]").with("deployed") { 'true' }
        expect(vm).to receive(:undeploy_link) { undeploy_link }
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
