require 'yajl'

module VCloudCloud
  module Steps
    class LoadAgentEnv < Step
      def perform(&block)
        vm = state[:vm] = client.reload state[:vm]
        metadata_link = "#{vm.metadata_link.href}/#{state[:env_metadata_key]}"
        metadata = client.invoke :get, metadata_link
        state[:env] = Yajl.load(metadata.value || '{}')
      end
    end
  end
end
