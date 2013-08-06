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
    
    def vapp_catalog
      catalog_link = org.catalog_link vapp_catalog_name
      raise CloudError, "Invalid vApp catalog name: #{vapp_catalog_name}" unless catalog_link
      resolve_link catalog_link
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
      @logger.debug "REST REQ #{method.to_s.upcase} #{params[:url]} #{params[:headers].inspect} #{params[:cookies].inspect}"
      response = RestClient::Request.execute params do |response, request, result, &block|
        @logger.debug "REST RES #{response.code} #{response.headers.inspect} #{response.body.inspect}"
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