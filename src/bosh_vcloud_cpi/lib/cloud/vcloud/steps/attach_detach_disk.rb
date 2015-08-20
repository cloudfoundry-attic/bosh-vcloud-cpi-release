module VCloudCloud
  module Steps
    class AttachDetachDisk < Step
      def perform(action, &block)
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'DiskAttachOrDetachParams'
        params.disk_href = state[:disk].href
        client.invoke_and_wait :post, state[:vm].send("#{action.to_s}_disk_link".to_sym),
            :payload => params,
            :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:DISK_ATTACH_DETACH_PARAMS] }
        state[:vm] = client.reload state[:vm]
        state[:disk] = client.reload state[:disk]
      end
    end
  end
end
