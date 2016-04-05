$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require "simplecov"
require "simplecov-rcov"

SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
end

require "yaml"
require "cloud"
require "cloud/vcloud"

module VCloudCloud
  module Test
    class << self
      def spec_asset(filename)
        File.expand_path(File.join(File.dirname(__FILE__), "assets", filename))
      end

      def test_configuration
        @@test_config ||= YAML.load_file(spec_asset("test-director-config.yml"))
      end

      def vcd_settings
        @@settings ||= get_vcd_settings
      end

      def director_cloud_properties
        test_configuration["cloud"]["properties"]
      end

      def get_vcd_settings
        vcds = director_cloud_properties["vcds"]
        raise "Invalid number of VCDs" unless vcds.size == 1
        vcds[0]
      end

      def test_deployment_manifest
        @@test_manifest ||=
          YAML.load_file(spec_asset("test-deployment-manifest.yml"))
      end

      def generate_unique_name
        SecureRandom.uuid
      end

      def compare_xml(a, b)
        a.diff(b) do |change, node|
          # " " Means no difference.  "+" means addition and "-" means deletion.
          return false if change != " " && node.to_s.strip().length != 0
        end
        true
      end

      def rest_logger(logger)
        rest_log_filename = File.join(File.dirname(
          logger.instance_eval { @logdev }.dev.path), "rest")
        log_file = File.open(rest_log_filename, "w")
        log_file.sync = true
        rest_logger = Logger.new(log_file || STDOUT)
        rest_logger.level = logger.level
        rest_logger.formatter = logger.formatter
        def rest_logger.<<(str)
          self.debug(str.chomp)
        end
        rest_logger
      end

      def delete_catalog_if_exists(client, catalog_name)
        client.flush_cache  # flush cached org which contains catalog list
        raw_catalog_link = client.org.catalog_link(catalog_name)
        return if raw_catalog_link.nil?
        catalog_link = VCloudSdk::Xml::Link.new(raw_catalog_link)
        return unless catalog_link
        catalog_id = catalog_link.href_id
        client.invoke(:delete, "/api/admin/catalog/#{catalog_id}")
      end
    end
  end

end



module VCloudSdk
  class CloudError < RuntimeError; end

  class VappSuspendedError < CloudError; end
  class VmSuspendedError < CloudError; end
  class VappPoweredOffError < CloudError; end

  class ObjectNotFoundError < CloudError; end

  class DiskNotFoundError < ObjectNotFoundError; end
  class CatalogMediaNotFoundError < ObjectNotFoundError; end

  class ApiError < CloudError; end

  class ApiRequestError < ApiError; end
  class ApiTimeoutError < ApiError; end

  module Test

    class << self
      def spec_asset(filename)
        File.expand_path(File.join(File.dirname(__FILE__), "assets", filename))
      end

      def test_configuration
        @@test_config ||= YAML.load_file(spec_asset("test-config.yml"))
      end

      def properties
        test_configuration["properties"]
      end

      def get_vcd_settings
        vcds = properties["vcds"]
        raise "Invalid number of VCDs" unless vcds.size == 1
        vcds[0]
      end

      def vcd_settings
        @@settings ||= get_vcd_settings
      end

      def generate_unique_name
        SecureRandom.uuid
      end

      def compare_xml(a, b)
        a.diff(b) do |change, node|
          # " " Means no difference.  "+" means addition and "-" means deletion.
          return false if change != " " && node.to_s.strip().length != 0
        end
        true
      end

      def rest_logger(logger)
        rest_log_filename = File.join(File.dirname(
          logger.instance_eval { @logdev }.dev.path), "rest")
        log_file = File.open(rest_log_filename, "w")
        log_file.sync = true
        rest_logger = Logger.new(log_file || STDOUT)
        rest_logger.level = logger.level
        rest_logger.formatter = logger.formatter
        def rest_logger.<<(str)
          self.debug(str.chomp)
        end
        rest_logger
      end
    end

  end

  class Config
    class << self
      def logger
        log_file = VCloudSdk::Test::properties["log_file"]
        FileUtils.mkdir_p(File.dirname(log_file))
        logger = Logger.new(log_file)
        logger.level = Logger::DEBUG
        logger
      end

      def configure(config)
      end
    end
  end

end

module Kernel

  def with_thread_name(name)
    old_name = Thread.current[:name]
    Thread.current[:name] = name
    yield
  ensure
    Thread.current[:name] = old_name
  end

end

module Bosh
  module Clouds
    class Config
      class << self
        def logger()
          log_file = VCloudCloud::Test::director_cloud_properties['log_file']
          FileUtils.mkdir_p(File.dirname(log_file))
          logger = Logger.new(log_file)  # You can switch to STDOUT if you don't want to use file for logging
          logger.level = Logger::DEBUG
          logger
        end

        def uuid()
          "Global variables named Config must die"
        end
      end
    end
  end
end
