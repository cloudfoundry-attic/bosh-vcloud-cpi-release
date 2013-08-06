module VCloudCloud
  module Steps
    class DiscardSuspendedState < Step
      def perform(ref, &block)
        entity = client.reload state[ref]
        if entity['status'] != VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          @logger.debug "#{entity.name} not suspended"
          return
        end
        client.invoke_and_wait :post, entity.discard_state
        state[ref] = client.reload entity
      end
    end
  end
end
