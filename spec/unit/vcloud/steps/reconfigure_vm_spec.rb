require "spec_helper"
module VCloudCloud
  module Steps
    describe ReconfigureVM do
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg}
        client.should_receive(:invoke_and_wait).with(
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
        vm.should_receive(:name=)
        vm.should_receive(:description=)
        vm.stub(:change_cpu_count)
        vm.stub(:change_memory)
        vm.stub(:add_hard_disk)
        vm.stub_chain("hardware_section.nics") { [] }
        vm.should_receive(:delete_nic)
        vm.should_receive(:add_nic)
        vm.should_receive(:connect_nic)
        vm.should_receive(:reconfigure_link) { reconfigure_link}
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
