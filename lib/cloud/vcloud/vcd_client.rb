require 'base64'
require 'uri'
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

      control = @entities['control'] || {}
      @wait_max       = control['wait_max'] || WAIT_MAX
      @wait_delay     = control['wait_delay'] || WAIT_DELAY
      @retry_max      = control['retry_max'] || RETRY_MAX
      @retry_delay    = control['retry_delay'] || RETRY_DELAY
      @cookie_timeout = control['cookie_timeout'] || COOKIE_TIMEOUT

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
        raise ObjectNotFoundError, "Invalid virtual datacenter name: #{vdc_name}" unless vdc_link
        resolve_link vdc_link
      end
    end

    # catalog should be either :vapp or :media
    def catalog(catalog_type)
      catalog_link = org.catalog_link @entities["#{catalog_type.to_s}_catalog"]
      raise ObjectNotFoundError, "Invalid catalog type: #{catalog_type}" unless catalog_link
      resolve_link catalog_link
    end

    # TODO we can discard type parameter since name should be
    # the unique identifier of a item in one catalog.
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
      raise ObjectNotFoundError, "Invalid catalog media: #{name}" unless catalog_media
      media = resolve_link catalog_media.entity
      [media, catalog_media]
    end

    def vapp_by_name(name)
      node = vdc.get_vapp name
      raise ObjectNotFoundError, "vApp #{name} does not exist" unless node
      resolve_link node.href
    end

    def resolve_link(link)
      invoke :get, link
    end

    def resolve_entity(id)
      session
      entity = invoke :get, "#{@entity_resolver_link.href}#{id}"
      raise ObjectNotFoundError, "Invalid entity urn: #{id}" unless entity
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
      (options[:no_wrap] || response.code == 204) ? nil : wrap_response(response)
    end

    def upload_stream(url, size, stream, options = {})
      session
      FileUploader.upload url, size, stream, options.merge({ :cookie => @cookie, :authorization => @auth_token })
    end

    def invoke_and_wait(*args)
      wait_task invoke(*args)
    end

    def wait_task(task, accept_failure = false)
      timed_loop do
        task = retry_for_network_issue { reload task }
        status = task.status.downcase
        @logger.debug "WAIT TASK #{task.urn} #{task.operation} #{status}"
        return task if status == VCloudSdk::Xml::TASK_STATUS[:SUCCESS]
        if [:ABORTED, :ERROR, :CANCELED].any? { |s| status == VCloudSdk::Xml::TASK_STATUS[s] }
          return task if accept_failure
          raise "Task #{task.urn} #{task.operation} completed unsuccessfully"
        end
      end
      task
    end

    def wait_entity(entity, accept_failure = false)
      entity.running_tasks.each do |task|
        wait_task task, accept_failure
      end if entity.running_tasks && !entity.running_tasks.empty?

      entity = reload entity

      # verify all tasks succeeded
      unless accept_failure || entity.tasks.nil? || entity.tasks.empty?
        failed_tasks = entity.tasks.find_all { |task| task.status.downcase != VCloudSdk::Xml::TASK_STATUS[:SUCCESS] }
        unless failed_tasks.empty?
          @logger.error "Failed tasks: #{failed_tasks}"
          raise "Some tasks failed"
        end
      end

      entity
    end

    def timed_loop(raise_exception = true)
      start_time = Time.now
      while Time.now - start_time < @wait_max
        yield
        sleep @wait_delay
      end
      raise TimeoutError if raise_exception
    end

    def flush_cache
      @cache.clear
    end

    private

    WAIT_MAX       = 300    # maximum wait seconds for a single task
    WAIT_DELAY     = 5      # delay in seconds for pooling next task status
    COOKIE_TIMEOUT = 1500   # timeout in seconds after which session must be re-created
    RETRY_MAX      = 3      # maximum attempts
    RETRY_DELAY    = 100    # delay of first retry, the next is * 2

    def cookie_available?
      @cookie && Time.now < @cookie_expiration
    end

    def session
      unless cookie_available?
        auth = "#{@user}@#{@entities['organization']}:#{@pass}"
        auth_header = "Basic #{Base64.encode64(auth)}"
        @session = invoke :post, '/api/sessions',
                    :headers => { :Authorization => auth_header, :content_type => 'application/x-www-form-urlencoded' },
                    :payload => URI.encode_www_form({ :Authorization => auth_header, :Accept => 'application/*+xml;version=5.1' }),
                    :login => true,
                    :with_response => true
        flush_cache
        @entity_resolver_link = @session.entity_resolver
        @org_link = @session.org_link @entities['organization']
      end
      @session
    end

    def wrap_response(response)
      VCloudSdk::Xml::WrapperFactory.wrap_document response
    end

    def retry_for_network_issue
      retries = 0
      delay = @retry_delay
      result = nil
      loop do
        begin
          result = yield
          break
        rescue RestClient::Exception => ex
          raise ex if retries >= @retry_max
          @logger.error "RestClient exception (retry after #{delay}ms): #{ex}"
          sleep(delay / 1000)
          delay *= 2
          retries += 1
        end
      end
      result
    end
  end
end
