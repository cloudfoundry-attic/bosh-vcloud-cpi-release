module VCloudCloud
  module Steps
    class PowerOnVM < Step
      def perform(&block)
        vm = client.reload state[:vm]
        if vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          @logger.debug "VM #{vm.name} already powered on"
          return
        end
        poweron_link = vm.power_on_link
        raise CloudError, "Virtual Machine #{vm.name} unable to power on" unless poweron_link
        client.invoke_and_wait :post, poweron_link
      end
    end
  end
end
