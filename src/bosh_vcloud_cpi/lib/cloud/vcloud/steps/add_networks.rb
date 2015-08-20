module VCloudCloud
  module Steps
    class AddNetworks < Step
      def perform(networks, &block)
        vapp = client.reload state[:vapp]
        org_networks = client.vdc.available_networks
        networks.each do |name|
          @logger.debug "NETWORK ADD #{name}"
          # find the corresponding accessible network object in org
          org_net = org_networks.find { |n| n.name == name }
          raise "Network #{name} not accesible to VDC #{client.vdc.name}" unless org_net
          # clone the configuration
          config = VCloudSdk::Xml::WrapperFactory.create_instance 'NetworkConfig'
          copy_network_settings client.reload(org_net), config, org_net.name, VCloudSdk::Xml::FENCE_MODES[:BRIDGED]
          vapp.network_config_section.add_network_config config
          client.invoke_and_wait :put, vapp.network_config_section,
                  :payload => vapp.network_config_section,
                  :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:NETWORK_CONFIG_SECTION] }
        end
        state[:vapp] = client.reload vapp
      end

      private

      def copy_network_settings(network, network_config, vapp_net_name, fence_mode)
        config_ip_scope = network_config.ip_scope
        net_ip_scope = network.ip_scope
        config_ip_scope.is_inherited = net_ip_scope.is_inherited?
        config_ip_scope.gateway= net_ip_scope.gateway
        config_ip_scope.netmask = net_ip_scope.netmask
        config_ip_scope.start_address = net_ip_scope.start_address if net_ip_scope.start_address
        config_ip_scope.end_address = net_ip_scope.end_address if net_ip_scope.end_address
        network_config.fence_mode = fence_mode
        network_config.parent_network['name'] = network.name
        network_config.parent_network['href'] = network.href
        network_config['networkName'] = vapp_net_name
      end
    end
  end
end
