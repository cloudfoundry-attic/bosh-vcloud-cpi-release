module VCloudSdk
  module Xml

    class AdminCatalog < Wrapper
      def add_item_link
        get_nodes("Link", {"type"=>ADMIN_MEDIA_TYPE[:CATALOG_ITEM],
          "rel"=>"add"}).first
      end

      def catalog_items(name = nil)
        if name
          get_nodes("CatalogItem", {"name" => name})
        else
          get_nodes("CatalogItem")
        end
      end

      def prerunning_tasks
        tasks.find_all { |t| PRE_RUNNING_TASK_STATUSES.include?(t.status) }
      end

      def running_tasks
        tasks.find_all {|t| RUNNING.include?(t.status)}
      end

      def tasks
        get_nodes("Task")
      end

      private

      RUNNING = [TASK_STATUS[:RUNNING], TASK_STATUS[:QUEUED],
                 TASK_STATUS[:PRE_RUNNING]]
    end
  end
end
