module VCloudCloud
  module Steps
    class PowerOff < Step
      def perform(ref, discard_suspend_state = false, &block)
        entity = client.reload state[ref]
        if entity['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
          @logger.debug "#{entity.name} already powered off"
          return
        end
        if discard_suspend_state && entity['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          client.invoke_and_wait :post, entity.discard_state
          entity = state[ref] = client.reload entity
        end
        poweroff_link = entity.power_off_link
        raise "#{entity.name} unable to power off" unless poweroff_link
        client.invoke_and_wait :post, poweroff_link
        state[ref] = client.reload entity
      end
    end
  end
end
