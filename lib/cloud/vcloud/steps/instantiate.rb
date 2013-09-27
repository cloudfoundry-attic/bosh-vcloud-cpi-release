module VCloudCloud
  module Steps
    # Create a vApp from a vApp template
    # Ref: http://pubs.vmware.com/vcd-51/index.jsp?topic=%2Fcom.vmware.vcloud.api.reference.doc_51%2Fdoc%2Foperations%2FPOST-InstantiateVAppTemplate.html
    class Instantiate < Step
      def perform(template_id, vapp_name, description, disk_locality, &block)
        catalog_item = client.resolve_entity template_id
        raise ObjectNotFoundError, "Invalid vApp template Id: #{template_id}" unless catalog_item
        template = client.resolve_link catalog_item.entity

        params = VCloudSdk::Xml::WrapperFactory.create_instance 'InstantiateVAppTemplateParams'
        params.name = vapp_name
        params.description = description
        params.source = template
        params.all_eulas_accepted = true
        params.linked_clone = false
        params.set_locality = locality_spec template, disk_locality

        vapp = client.invoke :post, client.vdc.instantiate_vapp_template_link, :payload => params

        state[:vapp] = client.wait_entity vapp
      end

      def rollback
        vapp = state[:vapp]
        if vapp
          @logger.debug "Requesting vApp: #{vapp.name}"

          # Note that when renaming vApp, the remove_link stays the same and points to
          # the original vApp. To avoid potential inconsistency, fetch vApp from the server.
          begin
            client.flush_cache  # flush cached vdc which contains vapp list
            vapp = client.vapp_by_name vapp.name
            link = vapp.remove_link true
            client.invoke_and_wait :delete, link if link
          rescue => ex
            @logger.debug(ex) if @logger
          end

          # remove the item from state
          state.delete :vapp
        end
      end

      private

      def locality_spec(template, disk_locality)
        locality = {}
        disk_locality.each do |disk|
          next unless disk
          template.vms.each do |vm|
            locality[vm] = disk
          end
        end
        locality
      end
    end
  end
end
