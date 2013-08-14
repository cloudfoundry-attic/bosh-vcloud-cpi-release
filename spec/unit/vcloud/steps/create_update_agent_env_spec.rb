require 'spec_helper'

shared_context "base" do
  let(:client) do
    client = double("vcloud client")
    client.stub(:logger) { Bosh::Clouds::Config.logger }
    client.stub(:reload) { |obj| obj }
    client
  end

  let(:vm) do
    vm = double("vm entity")
    vm.stub(:name) { "vm_name" }
    vm.stub(:urn) { "vm_urn" }
    vm
  end
end

module VCloudCloud
  module Steps

    describe CreateOrUpdateAgentEnv do
      include_context "base"

      describe ".perform" do
        it "create agent env" do
          network_name = "network1"
          network = {
            'cloud_properties' => {
              'name' => network_name
            }
          }
          nic = double("nic")
          nic.stub(:network) { network_name }
          nic.stub(:mac_address) { "mac_address" }
          nics = [ nic ]
          networks = { network_name => network }
          system_disk = double("system_disk")
          system_disk.stub(:disk_id) { "system_disk_id" }
          ephemeral_disk = double("disk1")
          ephemeral_disk.stub(:disk_id) { "disk1_id" }
          disks = [ephemeral_disk]

          environment = {}
          agent_properties = {}
          vm.stub_chain("hardware_section.nics") { nics }
          vm.stub_chain("hardware_section.hard_disks") { [system_disk, ephemeral_disk] }

          Transaction.perform("create_agent_env", client) do |s|
            s.state[:vm] = vm
            s.state[:disks] = [ system_disk ]
            s.state[:env] = environment
            s.next described_class, networks, environment, agent_properties
          end
        end

        it "raise error with multiple newly added disks" do
          networks = {}
          system_disk = double("system_disk")
          system_disk.stub(:disk_id) { "system_disk_id" }
          ephemeral_disk = double("disk1")
          ephemeral_disk2 = double("disk2")
          ephemeral_disk.stub(:disk_id) { "disk1_id" }
          disks = [ephemeral_disk]

          environment = {}
          agent_properties = {}
          vm.stub_chain("hardware_section.nics") { [] }
          vm.stub_chain("hardware_section.hard_disks") {
            [system_disk, ephemeral_disk, ephemeral_disk2] }

          expect {
            Transaction.perform("reboot", client) do |s|
              s.state[:vm] = vm
              s.state[:disks] = [ system_disk ]
              s.state[:env] = environment
              s.next described_class, networks, environment, agent_properties
            end
          }.to raise_error
        end
      end

      describe "#update_network_env" do
        it "evoke generate_network_env" do
          vm.stub_chain("hardware_section.nics") { [] }
          described_class.should_receive(:generate_network_env)

          described_class.update_network_env({}, vm, {})
        end
      end
    end
  end
end
