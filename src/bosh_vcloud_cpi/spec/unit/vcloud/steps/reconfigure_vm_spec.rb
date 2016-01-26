require "spec_helper"
module VCloudCloud
  module Steps
    describe ReconfigureVM do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg}
        expect(client).to receive(:invoke_and_wait).with(
          :post, reconfigure_link, anything)
        client
      end

      let(:vapp) do
        vapp = double("vapp")
        vapp
      end

      let(:reconfigure_link) { "reconfigure_link" }
      let(:vm) do
        vm = double("vm")
        expect(vm).to receive(:name=)
        expect(vm).to receive(:description=)
        allow(vm).to receive(:change_cpu_count)
        allow(vm).to receive(:change_memory)
        allow(vm).to receive(:add_hard_disk)
        allow(vm).to receive_message_chain("hardware_section.nics") { [] }
        expect(vm).to receive(:delete_nic)
        expect(vm).to receive(:add_nic)
        expect(vm).to receive(:connect_nic)
        expect(vm).to receive(:reconfigure_link) { reconfigure_link}
        vm
      end

      let(:resource_pool) { {
        "cpu" => 2,
        "ram" => 512,
        "disk" => 1024
      } }

      let(:networks) {
        {'vm' => {
          "cloud_properties" => { "name" => "vm"}
        }}
      }

      let(:name) { "vm_name" }
      let(:description) { "vm description" }

      it "reconfig a vm" do
        Transaction.perform("reboot", client) do |s|
          s.state[:vapp] = vapp
          s.state[:vm] = vm
          s.next described_class, name, description,
            resource_pool, networks
        end
      end
    end
  end
end
