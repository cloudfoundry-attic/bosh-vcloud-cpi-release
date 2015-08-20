module VCloudSdk
  module Xml

    class Link < Wrapper
      def name
        @root["name"]
      end

      def name=(name)
        @root["name"] = name
      end

      def rel
        @root["rel"]
      end

      def rel=(rel)
        @root["rel"] = rel
      end

      def type
        @root["type"]
      end

      def type=(type)
        @root["type"] = type
      end

      def href
        @root["href"]
      end

      def href=(href)
        @root["href"] = href
      end
    end
  end
end

