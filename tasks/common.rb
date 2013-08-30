require 'logger'
require 'yaml'
require 'common/thread_formatter'
require 'cloud'
require_relative '../lib/cloud/vcloud'

module CpiHelper
  class StubConfig
    attr_reader :logger

    def initialize(logger)
      @logger = logger
    end

    def db
    end

    def uuid
    end

    def task_checkpoint
    end
  end

  class Target
    attr_reader :cfg, :logger, :cpi

    def initialize(target)
      @cfg = target.is_a?(String) ? YAML.load_file(target) : target
      @logger = Logger.new ENV['LOGGER']
      @logger.formatter = ThreadFormatter.new
      Bosh::Clouds::Config.configure StubConfig.new(@logger)
      @cpi = @cfg && Bosh::Clouds::VCloud.new(@cfg)
    end

    def new_cpi
      Bosh::Clouds::VCloud.new @cfg
    end

    def client
      @cpi && @cpi.instance_eval { @delegate.instance_eval { client } }
    end

    def resolve_name(id)
      unless id.start_with?('urn:')
        catalogs = client.org.get_nodes 'Link', {'type' => 'application/vnd.vmware.vcloud.catalog+xml'}
        item = nil
        if catalogs && catalogs.any?
          catalogs.find do |catalog_link|
            catalog = nil
            begin
              catalog = client.resolve_link catalog_link
            rescue => ex
              @logger.warn "Ignoring #{ex}: #{ex.backtrace}"
            end
            item = catalog.catalog_items(id).first if catalog
            item
          end
        end
        if item
          item = client.resolve_link item.href
        end
        raise "Catalog item #{id} not found" unless item
        id = item.urn
      end
      id
    end
  end
end
