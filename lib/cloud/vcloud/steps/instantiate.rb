module VCloudCloud
  module Steps
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
