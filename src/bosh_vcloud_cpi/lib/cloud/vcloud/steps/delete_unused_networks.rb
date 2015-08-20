module VCloudCloud
  module Steps
    class DeleteUnusedNetworks < Step
      def perform(network_names_in_use, &block)
        vapp = client.reload state[:vapp]
        networks = vapp.network_config_section.network_configs.map { |n| n.network_name }
        unused = networks - network_names_in_use
        if unused && !unused.empty?
          unused.uniq.each do |n|
            vapp.network_config_section.delete_network_config n
          end
          client.invoke_and_wait :put, vapp.network_config_section,
                    :payload => vapp.network_config_section,
                    :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:NETWORK_CONFIG_SECTION] }
          state[:vapp] = client.reload vapp
        end
      end
    end
  end
end
