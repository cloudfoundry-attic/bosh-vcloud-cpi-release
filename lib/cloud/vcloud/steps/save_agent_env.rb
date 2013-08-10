require 'common/common'
require 'yajl'

module VCloudCloud
  module Steps
    class SaveAgentEnv < Step
      def perform(&block)
        vm = client.reload state[:vm]
        metadata_link = "#{vm.metadata_link.href}/#{state[:env_metadata_key]}"

        @logger.debug "AGENT_ENV #{vm.urn} #{state[:env].inspect}"

        env_json = Yajl::Encoder.encode state[:env]
        @logger.debug "ENV.ISO Content: #{env_json}"
        tmpdir = state[:tmpdir] = Dir.mktmpdir
        env_path = File.join tmpdir, 'env'
        iso_path = File.join tmpdir, 'env.iso'
        File.open(env_path, 'w') { |f| f.write env_json }
        output = `#{genisoimage} -o #{iso_path} #{env_path} 2>&1`
        @logger.debug "GENISOIMAGE #{output}"
        raise "genisoimage: #{$?.exitstatus}: #{output}" unless $?.success?

        metadata = VCloudSdk::Xml::WrapperFactory.create_instance 'MetadataValue'
        metadata.value = env_json
        client.invoke_and_wait :put, metadata_link,
                  :payload => metadata,
                  :headers => { :content_type => VCloudSdk::Xml::MEDIA_TYPE[:METADATA_ITEM_VALUE] }
        state[:vm] = client.reload state[:vm]
        state[:iso] = iso_path
      end

      def cleanup
        FileUtils.remove_entry_secure state[:tmpdir] if state[:tmpdir]
      end

      private

      def genisoimage  # TODO: this should exist in bosh_common, eventually
        @genisoimage ||= Bosh::Common.which(%w{genisoimage mkisofs})
      end
    end
  end
end
