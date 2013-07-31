module VCloudCloud
  module Steps
    class Delete < Step
      def perform(entity, force = false, &block)
        entity = client.reload entity
        link = entity.remove_link force
        raise "#{entity.name} can't be removed" unless link
        client.invoke_and_wait :delete, link
      end
    end
  end
end
