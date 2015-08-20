module VCloudCloud
  module Steps
    class StemcellInfo < Step
      def perform(image, &block)
        tmpdir = state[:stemcell_dir] = Dir.mktmpdir
        # examine files in the tarball
        `tar -C #{tmpdir} -xzf #{File.absolute_path(image)}`
        raise 'Invalid stemcell image' unless $?.success?
        files = Dir.glob File.join(tmpdir, '*.ovf')
        # stemcell should only include one .ovf file
        raise "Invalid stemcell image: having #{files.length} .ovf files" if files.length != 1
        state[:stemcell_ovf] = File.basename files[0]
      end

      def cleanup
        FileUtils.remove_entry_secure state[:stemcell_dir] if state[:stemcell_dir]
      end
    end
  end
end
