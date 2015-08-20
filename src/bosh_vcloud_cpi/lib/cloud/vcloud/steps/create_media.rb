module VCloudCloud
  module Steps
    class CreateMedia < Step
      def perform(name, iso, image_type, storage_profile, &block)
        # get the file properties
        media_file = File.new iso, 'rb'

        # create the media item
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'Media'
        params.name = name
        params.size = media_file.stat.size
        params.image_type = image_type
        params.storage_profile = storage_profile
        media = client.invoke :post, client.vdc.upload_media_link, :payload => params

        # cache the newly created item
        state[:media] = media
      end

      def rollback
        # get the time to delete
        media = state[:media]

        client.timed_loop do
          media = client.reload media
          if media.running_tasks.empty?
            # delete the item
            client.invoke_and_wait :delete, media.delete_link
            break
          else
            # need to wait for pending tasks to complete
            media = client.wait_entity media
          end
        end

        # remove the item from the state
        state.delete :media
      end
    end
  end
end