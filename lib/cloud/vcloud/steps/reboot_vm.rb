module VCloudCloud
  module Steps
    class RebootVM < Step
      def perform(&block)
        vm = client.reload state[:vm]
        reboot_link = vm.reboot_link
        raise CloudError, "Virtual Machine #{vm.name} unable to reboot" unless reboot_link
        client.invoke_and_wait :post, reboot_link
      end
    end
  end
end
