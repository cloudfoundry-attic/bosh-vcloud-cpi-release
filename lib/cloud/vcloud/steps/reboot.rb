module VCloudCloud
  module Steps
    class Reboot < Step
      def perform(ref, &block)
        entity = client.reload state[ref]
        reboot_link = entity.reboot_link
        raise "#{entity.name} unable to reboot" unless reboot_link
        client.invoke_and_wait :post, reboot_link
        state[ref] = client.reload entity
      end
    end
  end
end
