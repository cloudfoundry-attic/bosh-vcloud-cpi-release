module VCloudCloud
  module Steps
    class UploadCatalogMedia < Step
      def perform(name, iso, image_type, storage_profile, &block)
        media_file = File.new iso, 'rb'
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'Media'
        params.name = name
        params.size = media_file.stat.size
        params.image_type = image_type
        params.storage_profile = storage_profile
        media = client.invoke :post, client.vdc.upload_media_link, :payload => params
        incomplete_file = media.incomplete_files.pop
        client.upload_stream incomplete_file.upload_link.href, params.size, media_file
        media = client.reload media
        state[:media] = media
      end
    end
  end
end
