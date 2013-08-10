require 'cloud/errors'

module VCloudCloud
  class ObjectNotFoundError < StandardError
  end

  class TimeoutError < StandardError
  end
end
