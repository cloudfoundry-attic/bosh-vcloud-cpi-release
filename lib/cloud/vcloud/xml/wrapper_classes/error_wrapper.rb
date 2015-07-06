require 'cloud/vcloud/errors'

module VCloudSdk
  module Xml
    class Error < Wrapper

      def major_error
        @root["majorErrorCode"]
      end

      def minor_error
        @root["minorErrorCode"]
      end

      def error_msg
        @root["message"]
      end

      def exception(e)
        if error_msg.include? "There is already a VM named" and major_error == "400"
          raise VCloudCloud::ObjectExistsError
        else
          raise e
        end
      end
    end
  end
end

