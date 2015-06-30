require 'cloud/errors'

module VCloudCloud
  class ObjectNotFoundError < StandardError
  end

  class TimeoutError < StandardError
  end

  class ResponseError < StandardError

  end

  class ObjectExistsError < StandardError

  end
end
