module VCloudCloud
  module Steps
    class UploadTemplateFiles < Step
      def perform(&block)
        template = client.reload state[:vapp_template]
        # After uploading a file, we should reload the template object for incomplete_files list
        # until all files are uploaded.
        while template.files && !template.files.empty?
          template.incomplete_files.each do |file|
            if file.name.end_with?('.ovf')
              content = File.new(File.join(state[:stemcell_dir], state[:stemcell_ovf])).read
              client.invoke :put, file.upload_link.href,
                      :payload => content,
                      :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:OVF] },
                      :no_wrap => true
            else
              f = File.new File.join(state[:stemcell_dir], file.name)
              @logger.debug "UPLOAD #{f.path}: #{f.size}"
              client.upload_stream file.upload_link.href, f.size, f
            end
          end

          template = client.reload template
        end
        state[:vapp_template] = client.wait_entity template
      end
    end
  end
end
