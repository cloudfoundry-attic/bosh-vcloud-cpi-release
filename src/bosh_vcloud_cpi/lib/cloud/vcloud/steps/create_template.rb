module VCloudCloud
  module Steps
    class CreateTemplate < Step
      def perform(name, catalog_type, &block)
        catalog = client.catalog catalog_type

        params = VCloudSdk::Xml::WrapperFactory.create_instance 'UploadVAppTemplateParams'
        params.name = name
        upload_link = catalog.add_vapp_template_link
        catalog_item = client.invoke(
          :post,
          upload_link,
          :payload => params,
          :headers => {:content_type => upload_link.type}
        )

        template = client.invoke :get, catalog_item.entity.href

        # commit states
        state[:catalog_item] = catalog_item
        state[:vapp_template] = template
      end

      def rollback
        template = state[:vapp_template]
        if template
          if template.cancel_link
            client.invoke :post, template.cancel_link
            template = client.reload template
          end
          if template.remove_link
            client.invoke_and_wait :delete, template.remove_link
          end
        end
      end
    end
  end
end
