module VCloudCloud
  module Steps
    class StemcellInfo < Step
      def perform(image, &block)
        # examine files in the tarball
        output = `tar tvzf #{image}`
        raise CloudError, 'Invalid stemcell image' unless $?.success?
        files = output.split("\n").map do |line|
          fields = line.split ' '
          {
            name: fields[-1],
            size: fields[2].to_i
          }
        end
        
        # find .ovf files
        ovfs = files.select do |file|
          file[:name].end_with? '.ovf'
        end
        
        # stemcell should only include one .ovf file
        raise CloudError, "Invalid stemcell image: having #{ovfs.length} .ovf files" if ovfs.length != 1
        
        # commit states
        state[:stemcell_image] = image
        state[:stemcell_files] = files
        state[:stemcell_ovf] = ovfs[0]        
      end
    end
  end
end
