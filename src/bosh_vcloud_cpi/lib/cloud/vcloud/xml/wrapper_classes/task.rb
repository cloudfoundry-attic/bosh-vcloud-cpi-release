module VCloudSdk
  module Xml

    class Task < Wrapper
      def cancel_link
        get_nodes("Link", {"rel" => "task:cancel"}).first
      end

      def status
        self["status"]
      end

      # Friendly description of the task
      def operation
        self["operation"]
      end

      def details
        details = get_nodes("Details")
        return nil if details.nil?
        return details.collect {|d| d.content}.join
      end

      # Short form name of the operation
      def operation_name
        self["operationName"]
      end

      # Not all tasks will have progress
      def progress
        task_progress = get_nodes("Progress").first
        return task_progress.content unless task_progress.nil?
        nil
      end
      
      def start_time
        Time.parse(self["startTime"])
      end
    end

  end
end
