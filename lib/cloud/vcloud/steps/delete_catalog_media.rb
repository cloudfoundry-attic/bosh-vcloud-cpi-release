module VCloudCloud
  module Steps
    class DeleteCatalogMedia < Step
      def perform(name, &block)
        catalog_media = client.catalog_item :media, name, VCloudSdk::Xml::MEDIA_TYPE[:MEDIA]
        # return if doesn't exist
        return unless catalog_media
        media = client.resolve_link catalog_media.entity
        # TODO limit the number of retries
        while true
          @logger.info "DELETEMEDIA #{media.name}"
          media = client.reload media
          if media.running_tasks.empty?
            client.invoke_and_wait :delete, media.delete_link
            client.invoke :delete, catalog_media
            break
          else
            Transaction.perform 'DeletingCatalogMedia', client() do |s|
              media = client.wait_entity media
            end
            # TODO delay
          end
        end
      end
    end
  end
end
