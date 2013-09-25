module VCloudCloud
  module Steps
    # Undeployment means deallocation of all resources for a vApp/VM like CPU and memory from a vDC resource pool.
    # Undeploying a vApp automatically undeploys all of the virtual machines it contains.
    # https://www.vmware.com/support/vcd/doc/rest-api-doc-1.5-html/operations/POST-UndeployVApp.html
    class Undeploy < Step
      def perform(ref, &block)
        entity = client.reload state[ref]
        if entity['deployed'] == 'true'
          link = entity.undeploy_link
          raise "#{entity.name} can't be undeployed" unless link
          params = VCloudSdk::Xml::WrapperFactory.create_instance 'UndeployVAppParams'
          client.invoke_and_wait :post, link, :payload => params
          state[ref] = client.reload entity
        end
      end
    end
  end
end
