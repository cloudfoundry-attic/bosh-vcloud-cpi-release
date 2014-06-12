module VCloudCloud
  module Steps
    class CreateDisk < Step
      def perform(name, size_mb, vm, storage_profile, &block)
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'DiskCreateParams'
        params.name         = name
        params.size_bytes   = size_mb << 20 # VCD expects bytes
        params.bus_type     = VCloudSdk::Xml::HARDWARE_TYPE[:SCSI_CONTROLLER]
        params.bus_sub_type = VCloudSdk::Xml::BUS_SUB_TYPE[:LSILOGIC]
        params.add_locality vm if vm
        params.storage_profile = storage_profile if storage_profile
        disk = client.invoke :post, client.vdc.add_disk_link,
                  :payload => params,
                  :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:DISK_CREATE_PARAMS] }
        state[:disk] = client.wait_entity disk
      end

      def rollback
        disk = state[:disk]
        if disk
          link = disk.remove_link
          client.invoke_and_wait :delete, link if link

          # remove the item from state
          state.delete :disk
        end
      end
    end
  end
end
