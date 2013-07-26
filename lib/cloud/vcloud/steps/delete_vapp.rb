module VCloudCloud
  module Steps
    class DeleteVApp < Step
      def perform(vapp, force = false, &block)
        vapp = client.reload vapp
        client.invoke_and_wait :delete, vapp.delete_link(force)
      end
    end
  end
end
