module VCloudCloud
  class Cache
    def initialize
      @objects = {}
    end
    
    def get(id, &block)
      object = @objects[id]
      unless object
        object = block.call id
        @objects[id] = object
      end
      object
    end
    
    def clear
      @objects = {}
    end
  end
end
