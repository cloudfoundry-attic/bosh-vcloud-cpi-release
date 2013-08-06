require 'securerandom'

module VCloudCloud
  module Steps
    class CreateTemplate < Step
      def perform(&block)
        # generate vApp name
        vapp_name = "sc-#{SecureRandom.uuid}"
        
        # POST UploadVAppTemplateParams
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'UploadVAppTemplateParams'
        params.name = vapp_name
        template = client.invoke :post, client.vdc.upload_link, :payload => params
        
        # commit states
        state[:vapp_name] = vapp_name
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
            task = client.invoke :delete, template.remove_link
            WaitTasks.wait_task task, client
          end
        end
      end
    end
  end
end