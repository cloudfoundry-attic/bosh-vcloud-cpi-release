module VCloudCloud
  module Steps
    class UploadTemplateFiles < Step
      def perform(&block)
        template = client.reload state[:vapp_template]
        # After uploading a file, we should reload the template object for incomplete_files list
        # until all files are uploaded.
        while template.files && !template.files.empty?
          template.incomplete_files.each do |file|
            options = {}
            # .ovf is always named "descriptor.ovf" not the file in stemcell
            # so process specially, and with special content-type
            f = if file.name.end_with?('.ovf')
              options[:content_type] = VCloudSdk::Xml::MEDIA_TYPE[:OVF]
              state[:stemcell_ovf]
            else
              index = state[:stemcell_files].index { |f| f[:name] == file.name }
              raise CloudError, "File not found in stemcell image: #{file.name}" if index.nil?
              state[:stemcell_files][index]
            end
            @logger.debug "UPLOAD #{file.name}"
            client.upload_stream file.upload_link.href,
                                 f[:size],
                                 IO.popen("tar zxfO #{state[:stemcell_image]} #{f[:name]}"),
                                 options
          end
          template = client.reload template
        end
      end      
    end
  end
end