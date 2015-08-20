module VCloudSdk
  module Xml

    class Disk < Wrapper
      def bus_type=(value)
        @root["busType"] = value.to_s
      end

      def bus_sub_type=(value)
        @root["busSubType"] = value.to_s
      end

      def remove_link(force = false)
        link = get_nodes("Link", {"rel" => "remove"}, true).first
        return link unless force
        fix_if_invalid(link, "remove", MEDIA_TYPE[:DISK], "#{href}")
      end

      def name=(name)
        @root["name"] = name.to_s
      end

      def size_mb
        @root["size"].to_i/1024/1024
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
