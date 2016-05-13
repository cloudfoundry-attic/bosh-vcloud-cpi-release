require 'base64'
require 'uri'
require 'rest_client'
require 'common/common'

require_relative 'cache'
require_relative 'file_uploader'
require_relative 'xml/constants'
require_relative 'xml/wrapper'

module VCloudCloud
  class VCloudClient
    attr_reader :logger

    VCLOUD_VERSION_NUMBER = '5.5'

    def initialize(vcd_settings, logger)
      @logger = logger
      @url  = vcd_settings['url']
      @user = vcd_settings['user']
      @pass = vcd_settings['password']
      @entities = vcd_settings['entities']

      control = @entities['control'] || {}
      @wait_max           = control['wait_max'] || WAIT_MAX
      @wait_delay         = control['wait_delay'] || WAIT_DELAY
      @retry_max          = control['retry_max'] || RETRY_MAX
      @retry_delay        = control['retry_delay'] || RETRY_DELAY
      @cookie_timeout     = control['cookie_timeout'] || COOKIE_TIMEOUT
      @old_task_threshold = control['old_task_threshold'] || OLD_TASK_THRESHOLD

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

    # catalog_type should be either :vapp or :media
    def catalog_name(catalog_type)
      @entities["#{catalog_type.to_s}_catalog"]
    end

    def catalog(catalog_type)
      catalog_link = org.catalog_link catalog_name(catalog_type)
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
      vdc_link = org.vdc_link vdc_name
      raise ObjectNotFoundError, "Invalid virtual datacenter name: #{vdc_name}" unless vdc_link
      vdc_obj = resolve_link vdc_link
      node = vdc_obj.get_vapp name
      raise ObjectNotFoundError, "vApp #{name} does not exist" unless node
      @logger.debug "VAPP_BY_NAME - get a vapp name"
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
      session

      response = send_request method, path, options
      (options[:no_wrap] || response.code == 204) ? response : wrap_response(response)
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
        task = reload task
        status = task.status.downcase
        @logger.debug "WAIT TASK #{task.urn} #{task.operation} #{status}"
        return task if status == VCloudSdk::Xml::TASK_STATUS[:SUCCESS]
        if [:ABORTED, :ERROR, :CANCELED].any? { |s| status == VCloudSdk::Xml::TASK_STATUS[s] }
          return task if accept_failure
          raise "Task #{task.urn} #{task.operation} completed unsuccessfully, Details:#{task.details}"
        end
      end
      task
    end

    def wait_entity(entity, accept_failure = false)
      prerunning_tasks = entity.prerunning_tasks
      prerunning_tasks.each do |task|
        wait_task task, accept_failure
      end if prerunning_tasks && !prerunning_tasks.empty?

      running_tasks = entity.running_tasks
      running_tasks.each do |task|
        wait_task task, accept_failure
      end if running_tasks && !running_tasks.empty?

      entity = reload entity

      # verify all tasks succeeded
      unless entity.tasks.nil? || entity.tasks.empty?
        failed_tasks = get_failed_tasks(entity)
        unless failed_tasks.empty?
          @logger.debug "Failed tasks: #{failed_tasks}"
          unless accept_failure
            failed_tasks_info = failed_tasks.map { |t| "Task #{t.urn} #{t.operation}, Details:#{t.details}" }
            raise "Some tasks failed: #{failed_tasks_info.join('; ')}"
          end
        end
      end

      entity
    end
  
    def get_failed_tasks(entity)
      failed_tasks = entity.tasks.find_all { |task| task.status.downcase != VCloudSdk::Xml::TASK_STATUS[:SUCCESS] && old_task?(task) == false}
    end
    
    def old_task?(task)
      hour_ago = Time.now - @old_task_threshold

      if task.start_time < hour_ago then
        return true
      else
        return false
      end
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

    WAIT_MAX           = 300    # maximum wait seconds for a single task
    WAIT_DELAY         = 5      # delay in seconds for pooling next task status
    COOKIE_TIMEOUT     = 600    # default timeout in seconds, if not specified in configuration file, after which session must be re-created
    RETRY_MAX          = 3      # maximum attempts
    RETRY_DELAY        = 0.1    # wait time before retrying
    OLD_TASK_THRESHOLD = 600    # ignore failed tasks older than this (minutes)

    def cookie_available?
      @cookie && Time.now < @cookie_expiration
    end

    def login_url
      return @login_url if @login_url
      default_login_url = '/api/sessions'

      begin
        response = send_request :get, '/api/versions'
        url_node = wrap_response(response)
        if url_node.nil?
          @logger.warn "Unable to find version=#{VCLOUD_VERSION_NUMBER}. Default to #{default_login_url}"
          @login_url = default_login_url
        else
          @login_url = url_node.login_url.content
        end
      rescue => ex
        @logger.warn %Q{
          Caught exception when retrieving login url:
          #{ex.to_s}"

          Default to #{default_login_url}
        }

        @login_url = default_login_url
      end
    end

    def raise_specific_error(response, e)
      begin
        wrapped_response = VCloudSdk::Xml::WrapperFactory.wrap_document response.body
      rescue => ex
        @logger.debug "Wrap document raise error: #{ex.message}"
      end

      unless wrapped_response.nil?
        if wrapped_response.is_a?VCloudSdk::Xml::Error
          wrapped_response.exception(e)
        end
      end
      raise e
    end

    def send_request(method, path, options = {})
      path = path.href unless path.is_a?(String)

      params = {
          :method => method,
          :url => if path.start_with?('/')
            @url + path
          else
            path
          end,
          :headers => {
            :Accept => "application/*+xml;version=#{VCLOUD_VERSION_NUMBER}",
            :content_type => '*/*',
            'X-VMWARE-VCLOUD-CLIENT-REQUEST-ID' => SecureRandom.uuid
          }
      }
      params[:headers][:x_vcloud_authorization] = @auth_token if !options[:login] && @auth_token
      params[:cookies] = @cookie if !options[:login] && cookie_available?
      params[:payload] = options[:payload].to_s if options[:payload]
      params[:headers].merge! options[:headers] if options[:headers]

      errors = [RestClient::Exception, OpenSSL::SSL::SSLError, OpenSSL::X509::StoreError]
      Bosh::Common.retryable(sleep: @retry_delay, tries: 20, on: errors) do |tries, error|
        @logger.debug "REST REQ #{method.to_s.upcase} #{params[:url]} #{params[:headers].inspect} #{params[:cookies].inspect} #{params[:payload]}"
        @logger.warn "Attempting to retry #{method.to_s.upcase} request against #{params[:url]} after #{tries} unsuccessful attempts. Latest error: #{error.inspect}" if tries > 1

        RestClient::Request.execute params do |response, request, result, &block|
          @logger.debug "REST RES #{response.code} #{response.headers.inspect} #{response.body}"
          begin
            response.return! request, result, &block
          rescue => e
            raise_specific_error(response, e)
          end
        end
      end
    end

    def session
      unless cookie_available?
        auth = "#{@user}@#{@entities['organization']}:#{@pass}"
        auth_header = "Basic #{Base64.strict_encode64(auth)}"
        response = send_request(
          :post,
          login_url,
          :headers => {
            :Authorization => auth_header,
            :content_type => 'application/x-www-form-urlencoded'
          },
          :payload => URI.encode_www_form({
            :Authorization => auth_header,
            :Accept => "application/*+xml;version=#{VCLOUD_VERSION_NUMBER}"
          }),
          :with_response => true
        )

        @auth_token = response.headers[:x_vcloud_authorization]
        @cookie = response.cookies
        @cookie_expiration = Time.now + @cookie_timeout
        @session = wrap_response(response)

        flush_cache
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
