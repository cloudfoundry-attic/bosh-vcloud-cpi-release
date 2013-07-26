module VCloudCloud
  module Steps
    class PowerOnVApp < Step
      def perform(&block)
        vapp = client.reload state[:vapp]
        @logger.debug "POWERONVAPP #{vapp.name}: #{vapp['status']}"
        return if vapp['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
        raise CloudError, "vApp #{vapp.name} not in a state to be powered on." unless vapp.power_on_link
        client.invoke_and_wait :post, vapp.power_on_link
      end
    end
  end
end
