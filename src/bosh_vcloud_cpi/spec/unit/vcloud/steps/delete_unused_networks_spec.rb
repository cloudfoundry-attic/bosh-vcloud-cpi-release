require "spec_helper"

module VCloudCloud
  module Steps
    describe DeleteUnusedNetworks do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg}
        client
      end

      let(:vapp) do
        vapp = double("vapp")
        vapp
      end

      let(:network_in_use_name) { "network_in_use" }
      let(:network_in_use) do
        name = network_in_use_name
        network = double(name)
        allow(network).to receive(:network_name) { name }
        network
      end

      let(:network_not_used_name) { "network_not_used" }
      let(:network_not_used) do
        name = network_not_used_name
        network = double(name)
        allow(network).to receive(:network_name) { name }
        network
      end

      let(:network_config_section) do
        network_config_section = double("network_config_section")
        network_config_section
      end


      describe ".perform" do
        it "deletes unused networks" do
          expect(network_config_section).to receive(:network_configs) {
            [ network_not_used, network_in_use ]
          }
          expect(network_config_section).to receive(:delete_network_config).with(
            network_not_used_name
          )
          allow(vapp).to receive(:network_config_section) { network_config_section }

          state = { vapp: vapp }
          networks_in_use = [ network_in_use ]
          expect(client).to receive(:invoke_and_wait).with(
            :put, network_config_section, anything
          )

          described_class.new(state, client).perform(
            [ network_in_use_name ]
          )
        end
      end
    end
  end
end
