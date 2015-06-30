module VCloudCloud
  class FileMutex
    def initialize(location)
      @location = File.join(location, 'file.lock')
    end

    def synchronize
      yield if block_given?
      # File.open(@location, File::RDWR|File::CREAT, 0644) do |f|
      #   f.flock(File::LOCK_EX)
      #   yield if block_given?
      #   f.flock(File::LOCK_UN)
      # end
    end
  end
end

