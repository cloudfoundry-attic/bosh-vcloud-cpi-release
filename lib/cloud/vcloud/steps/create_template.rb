module VCloudCloud
  module Steps
    class CreateTemplate < Step
      def perform(name, &block)
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'UploadVAppTemplateParams'
        params.name = name
        template = client.invoke :post, client.vdc.upload_link, :payload => params

        # commit states
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
