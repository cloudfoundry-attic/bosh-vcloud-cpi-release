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
    
    def perform(&block)
      with_thread_name @name do
        # Perform all steps guarded by exception handler
        begin
          block.call self
        rescue => ex
          @logger.error "FAIL #{@name}"
          reverse_steps :rollback
          raise ex
        ensure
          reverse_steps :cleanup
        end
      end
      @state
    end
    
    def self.perform(name, client = nil, &block)
      new(name, client).perform &block
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
require_relative 'steps/wait_tasks'