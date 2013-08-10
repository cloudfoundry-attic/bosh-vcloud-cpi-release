module VCloudCloud
  module Steps
    class ReconfigureVM < Step
      def perform(name, description, resource_pool, networks, &block)
        vapp = state[:vapp] = client.reload state[:vapp]
        vm = state[:vm] = client.reload state[:vm]

        vm.name = name unless name.nil?
        vm.description = description unless description.nil?

        unless resource_pool.nil?
          vm.change_cpu_count Integer(resource_pool['cpu'])
          vm.change_memory Integer(resource_pool['ram'])
          vm.add_hard_disk Integer(resource_pool['disk'])
        end

        unless networks.nil?
          vm.delete_nic *vm.hardware_section.nics

          networks.values.each_with_index do |network, nic_index|
            name = network['cloud_properties']['name']
            vm.add_nic nic_index, name, VCloudSdk::Xml::IP_ADDRESSING_MODE[:MANUAL], network['ip']
            vm.connect_nic nic_index, name, VCloudSdk::Xml::IP_ADDRESSING_MODE[:MANUAL], network['ip']
          end
        end

        client.invoke_and_wait :post, vm.reconfigure_link,
                :payload => vm,
                :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:VM] }

        state[:vm] = client.reload vm
      end
    end
  end
end
