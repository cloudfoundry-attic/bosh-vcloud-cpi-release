module VCloudSdk
  module Xml

    class Catalog < Wrapper
      def add_item_link
        get_nodes("Link", {"type" => MEDIA_TYPE[:CATALOG_ITEM],
                           "rel"=>"add"}).first
      end

      def catalog_items(name = nil)
        if name
          get_nodes("CatalogItem", {"name" => name})
        else
          get_nodes("CatalogItem")
        end
      end
    end

  end
end
