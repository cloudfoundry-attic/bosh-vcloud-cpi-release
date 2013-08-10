module VCloudCloud
  module Steps
    class Recompose < Step
      def perform(container_vapp, &block)
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'RecomposeVAppParams'
        params.name = container_vapp.name
        params.all_eulas_accepted = true
        params.add_source_item state[:vm].href

        # HACK: Workaround. recomposeLink is not available when vapp is running (so force construct the link)
        recompose_vapp_link = container_vapp.recompose_vapp_link true
        client.invoke_and_wait :post, recompose_vapp_link, :payload => params
      end
    end
  end
end
