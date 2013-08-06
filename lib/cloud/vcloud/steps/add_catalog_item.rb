module VCloudCloud
  module Steps
    class AddCatalogItem < Step
      def perform(item, &block)
        catalog = client.vapp_catalog
        catalog_item = VCloudSdk::Xml::WrapperFactory.create_instance 'CatalogItem'
        catalog_item.name = item.name
        catalog_item.entity = item
        result = client.invoke :post,
                               catalog.add_item_link,
                               :payload => catalog_item,
                               :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:CATALOG_ITEM] }
        
        state[:catalog_item] = result
      end
    end
  end
end
