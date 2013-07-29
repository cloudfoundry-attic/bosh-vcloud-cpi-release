module VCloudCloud
  module Steps
    class PowerOn < Step
      def perform(ref, &block)
        entity = client.reload state[ref]
        if entity['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          @logger.debug "#{entity.name} already powered on"
          return
        end
        poweron_link = entity.power_on_link
        raise CloudError, "#{entity.name} unable to power on" unless poweron_link
        client.invoke_and_wait :post, poweron_link
        state[ref] = client.reload entity
      end
    end
  end
end
