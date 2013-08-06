module VCloudCloud
  module Steps
    class WaitTasks < Step
      WAIT_DELAY = 15
      
      def perform(object, options = {}, &block)
        object.running_tasks.each do |task|
          WaitTasks.wait_task task, client
        end
        
        # verify all tasks succeeded
        object = client.reload object
        failed_tasks = object.tasks.find_all { |task| task.status.downcase != VCloudSdk::Xml::TASK_STATUS[:SUCCESS] }
        unless failed_tasks.empty?
          @logger.error "Failed tasks: #{failed_tasks}"
          raise CloudError, "Error uploading vApp Template"
        end
      end
      
      def self.wait_task(task, client)
        # TODO timeout wait instead of infinite wait
        while true
          status = task.status.downcase
          client.logger.debug "WAIT TASK #{task.urn} #{task.operation} #{status}"
          break if status == VCloudSdk::Xml::TASK_STATUS[:SUCCESS]
          if [:ABORTED, :ERROR, :CANCELED].any? { |s| status == VCloudSdk::Xml::TASK_STATUS[s] }
            raise CloudError, "Task #{task.urn} #{task.operation} completed unsuccessfully"
          end
          sleep WAIT_DELAY  # TODO WAIT_DELAY from configuration
          task = client.reload task
        end     
      end
    end
  end
end
