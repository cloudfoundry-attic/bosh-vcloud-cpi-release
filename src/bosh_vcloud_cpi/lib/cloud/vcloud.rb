require_relative 'vcloud/cloud'

module Bosh
  module Clouds
    Vcloud = ::VCloudCloud::Cloud # alias name for dynamic plugin loading
  end
end
