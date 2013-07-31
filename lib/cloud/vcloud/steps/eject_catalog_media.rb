module VCloudCloud
  module Steps
    class EjectCatalogMedia < Step
      def perform(name, &block)
        catalog_media = client.catalog_item :media, name, VCloudSdk::Xml::MEDIA_TYPE[:MEDIA]
        # return if doesn't exist
        return unless catalog_media
        media = client.resolve_link catalog_media.entity
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'MediaInsertOrEjectParams'
        params.media_href = media.href
        vm = state[:vm]
        # TODO limit the number of retries
        while true
          @logger.debug "EJECTMEDIA #{media.name} from VM #{vm.name}"
          media = client.reload media
          vm = client.reload vm
          if media.running_tasks.empty?
            client.invoke_and_wait :post, vm.eject_media_link,
                    :payload => params,
                    :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:MEDIA_INSERT_EJECT_PARAMS] }
            break
          else
            Transaction.perform 'EjectingCatalogMedia', client() do |s|
              media = client.wait_entity media
            end
            # TODO delay
          end
        end
        
        state[:vm] = client.reload vm
      end
    end
  end
end
