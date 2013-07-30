require 'base64'
require 'rest_client'
require_relative 'cache'
require_relative 'file_uploader'
require_relative 'xml/constants'
require_relative 'xml/wrapper'

module VCloudCloud
  class VCloudClient
    attr_reader :logger

    def initialize(vcd_settings, logger)
      @logger = logger
      @url  = vcd_settings['url']
      @user = vcd_settings['user']
      @pass = vcd_settings['password']
      @entities = vcd_settings['entities']
      @cache = Cache.new
    end
    
    def org_name
      @entities['organization']
    end
    
    def vdc_name
      @entities['virtual_datacenter']
    end
    
    def vapp_catalog_name
      @entities['vapp_catalog']
    end
    
    def media_catalog_name
      @entities['media_catalog']
    end
    
    def org
      @cache.get :org do
        session
        resolve_link @org_link
      end
    end

    def vdc
      @cache.get :vdc do
        vdc_link = org.vdc_link vdc_name
        raise CloudError, "Invalid virtual datacenter name: #{vdc_name}" unless vdc_link
        resolve_link vdc_link
      end
    end
    
    # catalog should be either :vapp or :media
    def catalog(catalog_type)
      catalog_link = org.catalog_link @entities["#{catalog_type.to_s}_catalog"]
      raise CloudError, "Invalid catalog type: #{catalog_type}" unless catalog_link      
      resolve_link catalog_link
    end

    def catalog_item(catalog_type, name, type)
      cat = catalog catalog_type
      items = cat.catalog_items name
      result = nil
      items.any? do |item|
        object = resolve_link item
        result = object if object.entity['type'] == type
        result
      end if items
      result
    end
    
    def media(name)
      catalog_media = catalog_item :media, name, VCloudSdk::Xml::MEDIA_TYPE[:MEDIA]
      raise CloudError, "Invalid catalog media: #{name}" unless catalog_media
      media = resolve_link catalog_media.entity
      [media, catalog_media]
    end
    
    def vapp_by_name(name)
      node = vdc.get_vapp name
      raise CloudError, "vApp #{name} does not exist" unless node
      resolve_link node.href
    end
    
    def resolve_link(link)
      invoke :get, link
    end
    
    def resolve_entity(id)
      session
      entity = invoke :get, "#{@entity_resolver_link.href}#{id}"
      raise CloudError, "Invalid entity urn: #{id}" unless entity
      resolve_link entity.link
    end
    
    def reload(object)
      resolve_link object.href
    end
    
    def invoke(method, path, options = {})
      session unless options[:login]
      
      path = path.href unless path.is_a?(String)

      params = {
        :method => method,
        :url => if path.start_with?('/')
            @url + path
          else
            path
          end,
        :headers => {
          :Accept => 'application/*+xml;version=5.1',
          :content_type => '*/*'
        }
      }
      params[:headers][:x_vcloud_authorization] = @auth_token if !options[:login] && @auth_token
      params[:cookies] = @cookie if !options[:login] && cookie_available?
      params[:payload] = options[:payload].to_s if options[:payload]
      params[:headers].merge! options[:headers] if options[:headers]
      @logger.debug "REST REQ #{method.to_s.upcase} #{params[:url]} #{params[:headers].inspect} #{params[:cookies].inspect} #{params[:payload]}"
      response = RestClient::Request.execute params do |response, request, result, &block|
        @logger.debug "REST RES #{response.code} #{response.headers.inspect} #{response.body}"
        response.return! request, result, &block
      end
      if options[:login]
        @auth_token = response.headers[:x_vcloud_authorization]
        @cookie = response.cookies
        @cookie_expiration = Time.now + COOKIE_TIMEOUT  # TODO COOKIE_TIMEOUT should be from configuration
      end
      response.code == 204 ? nil : wrap_response(response)
    end

    def upload_stream(url, size, stream, options = {})
      session
      FileUploader.upload url, size, stream, @cookie, options
    end
    
    def invoke_and_wait(*args)
      task = invoke *args
      Steps::WaitTasks.wait_task task, self
    end
    
    def wait_task(task, accept_failure = false)
      # TODO timeout wait instead of infinite wait
      while true
        status = task.status.downcase
        @logger.debug "WAIT TASK #{task.urn} #{task.operation} #{status}"
        break if status == VCloudSdk::Xml::TASK_STATUS[:SUCCESS]
        if [:ABORTED, :ERROR, :CANCELED].any? { |s| status == VCloudSdk::Xml::TASK_STATUS[s] }
          return if accept_failure
          raise CloudError, "Task #{task.urn} #{task.operation} completed unsuccessfully"
        end
        sleep WAIT_DELAY  # TODO WAIT_DELAY from configuration
        task = reload task
      end
      
      task
    end
    
    def wait_entity(entity, accept_failure = false)
      return if !entity.running_tasks || entity.running_tasks.empty?
      entity.running_tasks.each do |task|
          wait_task task, accept_failure
      end
        
      entity = reload entity
      
      # verify all tasks succeeded
      unless accept_failure
        failed_tasks = entity.tasks.find_all { |task| task.status.downcase != VCloudSdk::Xml::TASK_STATUS[:SUCCESS] }
        unless failed_tasks.empty?
          @logger.error "Failed tasks: #{failed_tasks}"
          raise CloudError, "Some tasks failed"
        end
      end
      
      entity
    end
    
    private
    
    COOKIE_TIMEOUT = 1500
    
    def cookie_available?
      @cookie && Time.now < @cookie_expiration
    end
    
    def session
      unless cookie_available?
        auth = "#{@user}@#{@entities['organization']}:#{@pass}"
        auth_header = "Basic #{Base64.encode64(auth)}"
        @session = invoke :post, '/api/sessions',
                    :headers => { :Authorization => auth_header },
                    :login => true,
                    :with_response => true
        @cache.clear
        @entity_resolver_link = @session.entity_resolver
        @org_link = @session.org_link @entities['organization']
      end
      @session
    end

    def wrap_response(response)
      VCloudSdk::Xml::WrapperFactory.wrap_document response
    end
  end
end