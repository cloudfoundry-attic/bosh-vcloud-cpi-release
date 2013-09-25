module VCloudCloud
  module Steps
    # Recompose a vApp to add or remove VMs.
    # Ref: http://pubs.vmware.com/vcd-51/index.jsp#operations/POST-RecomposeVApp.html

    class Recompose < Step
      def perform(name, container_vapp, vm = nil, &block)
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'RecomposeVAppParams'
        params.name = name
        params.all_eulas_accepted = true
        params.add_source_item vm.href if vm

        # HACK: Workaround. recomposeLink is not available when vapp is running (so force construct the link)
        recompose_vapp_link = container_vapp.recompose_vapp_link true
        client.invoke_and_wait :post, recompose_vapp_link, :payload => params
      end
    end
  end
end
