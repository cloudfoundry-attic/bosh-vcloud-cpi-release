module VCloudCloud
  module Steps
    class Undeploy < Step
      def perform(entity, &block)
        entity = client.reload entity
        if entity['deployed'] == 'true'
          link = entity.undeploy_link
          raise "#{entity.name} can't be undeployed" unless link
          params = VCloudSdk::Xml::WrapperFactory.create_instance 'UndeployVAppParams'
          client.invoke_and_wait :post, link, :payload => params
        end
      end
    end
  end
end
