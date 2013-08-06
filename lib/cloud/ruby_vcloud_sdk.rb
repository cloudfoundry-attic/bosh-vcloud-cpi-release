require "logger"

module VCloudSdk; end

require_relative "ruby_vcloud_sdk/xml/constants"
require_relative "ruby_vcloud_sdk/xml/wrapper"
require_relative "ruby_vcloud_sdk/xml/wrapper_classes"

require_relative "ruby_vcloud_sdk/config"
require_relative "ruby_vcloud_sdk/errors"
require_relative "ruby_vcloud_sdk/util"
require_relative "ruby_vcloud_sdk/client"
require_relative "ruby_vcloud_sdk/ovf_directory"

require_relative "ruby_vcloud_sdk/connection/connection"
require_relative "ruby_vcloud_sdk/connection/file_uploader"
