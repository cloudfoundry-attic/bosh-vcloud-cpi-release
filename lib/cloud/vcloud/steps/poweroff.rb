module VCloudCloud
  module Steps
    class PowerOff < Step
      def perform(ref, &block)
        entity = client.reload state[ref]
        if entity['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
          @logger.debug "#{entity.name} already powered off"
          return
        end
        poweroff_link = entity.power_off_link
        raise CloudError, "#{entity.name} unable to power off" unless poweroff_link
        client.invoke_and_wait :post, poweroff_link
        state[ref] = client.reload entity
      end
    end
  end
end
