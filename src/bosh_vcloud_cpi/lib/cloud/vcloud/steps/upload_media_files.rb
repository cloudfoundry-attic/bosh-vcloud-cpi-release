module VCloudCloud
  module Steps
    class UploadMediaFiles < Step
      def perform(iso, &block)
        # get the file to upload
        media_file = File.new iso, 'rb'

        # upload the file
        media = state[:media]
        incomplete_file = media.incomplete_files.pop
        client.upload_stream incomplete_file.upload_link.href, media_file.stat.size, media_file

        # reload the media file
        state[:media] = client.reload media
      end
    end
  end
end
