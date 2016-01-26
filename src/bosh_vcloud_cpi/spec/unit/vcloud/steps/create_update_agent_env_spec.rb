require 'spec_helper'

shared_context "base" do
  let(:client) do
    client = double("vcloud client")
    allow(client).to receive(:logger).and_return Bosh::Clouds::Config.logger
    allow(client).to receive(:reload) { |obj| obj }
    client
  end

  let(:vm) do
    vm = double("vm entity")
    allow(vm).to receive(:name).and_return "vm_name"
    allow(vm).to receive(:urn).and_return "vm_urn"
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
          expect(nic).to receive(:network).and_return network_name
          expect(nic).to receive(:mac_address).and_return "mac_address"
          nics = [ nic ]
          networks = { network_name => network }
          system_disk = double("system_disk")
          expect(system_disk).to receive(:disk_id).and_return "system_disk_id"
          ephemeral_disk = double("disk1")
          expect(ephemeral_disk).to receive(:disk_id).and_return "disk1_id"
          disks = [ephemeral_disk]

          environment = {}
          agent_properties = {}
          allow(vm).to receive_message_chain("hardware_section.nics").and_return nics
          allow(vm).to receive_message_chain("hardware_section.hard_disks").and_return [system_disk, ephemeral_disk]

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
          allow(system_disk).to receive(:disk_id).and_return "system_disk_id"
          ephemeral_disk = double("disk1")
          ephemeral_disk2 = double("disk2")
          allow(ephemeral_disk).to receive(:disk_id).and_return "disk1_id"
          disks = [ephemeral_disk]

          environment = {}
          agent_properties = {}
          allow(vm).to receive_message_chain("hardware_section.nics").and_return []
          allow(vm).to receive_message_chain("hardware_section.hard_disks").and_return [system_disk, ephemeral_disk, ephemeral_disk2]

          expect {
            Transaction.perform("reboot", client) do |s|
              s.state[:vm] = vm
              s.state[:disks] = [ system_disk ]
              s.state[:env] = environment
              s.next described_class, networks, environment, agent_properties
            end
          }.to raise_error RuntimeError
        end
      end

      describe "#update_network_env" do
        it "evoke generate_network_env" do
          allow(vm).to receive_message_chain("hardware_section.nics").and_return []
          expect(described_class).to receive(:generate_network_env)

          described_class.update_network_env({}, vm, {})
        end
      end
    end
  end
end
