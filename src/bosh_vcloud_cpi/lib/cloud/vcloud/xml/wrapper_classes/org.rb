module VCloudSdk
  module Xml

    class Org < Wrapper

      def vdc_link(name)
        get_nodes("Link",
                  { "type" => MEDIA_TYPE[:VDC],
                    "name" => name},
                  true).first
      end

      def catalog_link(name)
        get_nodes("Link",
                  { "type" => MEDIA_TYPE[:CATALOG],
                    "name" => name},
                  true).first
      end

      def add_catalog_link
        link = get_nodes("Link",
                         {"rel" => "add",
                          "type" => ADMIN_MEDIA_TYPE[:ADMIN_CATALOG]},
                         true).first
        if !link
          raise "Couldn't find add catalog link in #{@root}"
        end
        return link
      end
    end
  end
end
