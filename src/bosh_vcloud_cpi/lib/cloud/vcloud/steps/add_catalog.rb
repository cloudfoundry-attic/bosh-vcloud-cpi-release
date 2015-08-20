module VCloudCloud
  module Steps
    class AddCatalog < Step
      def perform(name, &block)
        catalog = VCloudSdk::Xml::WrapperFactory.create_instance 'AdminCatalog'
        catalog.name = name
        link = client.org.add_catalog_link
        begin
          result = client.invoke :post,
                                 link,
                                 :payload => catalog,
                                 :headers => { :content_type => link.type }
          catalog = client.wait_entity result
          client.flush_cache
          return catalog
        rescue RestClient::BadRequest
          # check if catalog already exists; if so, this is not an error
          client.flush_cache
          catalog = client.org.catalog_link(name)
          if catalog
            return client.resolve_link(catalog)
          end
          raise
        end
      end

      def rollback
        # rollback is purposely not implemented because it could affect VMs
        # in other deployments that share the same catalog
      end
    end
  end
end
