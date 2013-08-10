module VCloudCloud
  module Steps
    class CreateAgentEnv < Step
      def perform(networks, environment, agent_properties, &block)
        vm = state[:vm] = client.reload state[:vm]

        system_disk = state[:disks][0]
        ephemeral_disk = get_newly_added_disk vm
        state[:env] = {
          'vm' => { 'name' => vm.name, 'id' => vm.urn },
          'agent_id' => vm.name,
          'disks' => {
            'system' => system_disk.disk_id,
            'ephemeral' => ephemeral_disk.disk_id,
            'persistent' => {}
          },
          'networks' => CreateAgentEnv.generate_network_env(vm.hardware_section.nics, networks),
          'env' => environment || {}
        }.merge! agent_properties
      end

      private

      def get_newly_added_disk(vm)
        disks = vm.hardware_section.hard_disks
        newly_added = disks - state[:disks]
        if newly_added.size != 1
          raise "Expecting #{state[:disks].size + 1} disks, found #{disks.size}"
        end
        newly_added[0]
      end

      def self.generate_network_env(nics, networks)
        nic_net = {}
        nics.each do |nic|
          nic_net[nic.network] = nic
        end

        network_env = {}
        networks.each do |network_name, network|
          network_entry = network.dup
          v_network_name = network['cloud_properties']['name']
          nic = nic_net[v_network_name]
          next if nic.nil?
          network_entry['mac'] = nic.mac_address
          network_env[network_name] = network_entry
        end
        network_env
      end

      public

      def self.update_network_env(env, vm, networks)
        env['networks'] = generate_network_env vm.hardware_section.nics, networks
      end
    end
  end
end
