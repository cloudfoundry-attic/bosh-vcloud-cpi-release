module VCloudCloud
  module Steps
    class DiscardSuspendedState < Step
      def perform(&block)
        vm = client.reload state[:vm]
        if vm['status'] != VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          @logger.debug "VM #{vm.name} not suspended"
          return
        end
        client.invoke_and_wait :post, vm.discard_state
      end
    end
  end
end
