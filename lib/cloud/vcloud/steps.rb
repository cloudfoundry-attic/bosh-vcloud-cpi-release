require 'common/thread_formatter' # for with_thread_name

module VCloudCloud
  # Abstract Step
  class Step
    attr_reader :state, :client
    
    def initialize(state, client)
      @client = client
      @logger = client.logger
      @state = state
    end
    
    def rollback
    end
    
    def cleanup
    end
  end
  
  # Transactional step execution engine
  class Transaction
    attr_reader :name, :state, :client
    
    def initialize(name, client)
      @name = name
      @client = client
      @logger = client.logger
      @state = {}
      @steps = []
    end
    
    def next(step_class, *args, &block)
      step = step_class.new @state, @client
      @steps << step
      @logger.debug "STEP #{step_class.to_s}"
      step.perform *args, &block
    end
    
    def perform(options = {}, &block)
      with_thread_name @name do
        # Perform all steps guarded by exception handler
        begin
          block.call self
        rescue => ex
          @logger.error "FAIL #{@name} #{ex}"
          reverse_steps :rollback
          raise ex unless options[:no_throws]
          @state[:error] = ex
        ensure
          reverse_steps :cleanup
        end
      end
      @state
    end
    
    def self.perform(name, client = nil, options = {}, &block)
      new(name, client).perform options, &block
    end
    
    private
    
    def reverse_steps(method)
      @steps.reverse_each do |step|
        begin
          @logger.debug "REV #{method.to_s.upcase} #{step.class.to_s}"
          step.send method
        rescue => ex
          @logger.error(ex) if @logger
        end
      end
    end
  end
end

require_relative 'steps/stemcell_info'
require_relative 'steps/create_template'
require_relative 'steps/upload_template_files'
require_relative 'steps/add_catalog_item'
require_relative 'steps/instantiate'
require_relative 'steps/recompose'
require_relative 'steps/delete'
require_relative 'steps/undeploy'
require_relative 'steps/add_networks'
require_relative 'steps/delete_unused_networks'
require_relative 'steps/reconfigure_vm'
require_relative 'steps/create_agent_env'
require_relative 'steps/load_agent_env'
require_relative 'steps/save_agent_env'
require_relative 'steps/eject_catalog_media'
require_relative 'steps/delete_catalog_media'
require_relative 'steps/upload_catalog_media'
require_relative 'steps/insert_catalog_media'
require_relative 'steps/poweron'
require_relative 'steps/poweroff'
require_relative 'steps/discard_suspended_state'
require_relative 'steps/reboot'
require_relative 'steps/create_disk'
require_relative 'steps/attach_detach_disk'
