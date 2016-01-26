require "spec_helper"

module VCloudCloud
  module Steps
    describe LoadAgentEnv do
      let(:client) do
        client = double("client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg}
        client
      end

      let(:metadata) do
        metadata = double("metdadata")
        allow(metadata).to receive(:value) { '{"key":"value"}' }
        metadata
      end

      let(:vm) do
        vm = double("vm")
        vm
      end

      describe ".perform" do
        it "load agent environment" do
          metadata_link = "meta_data_link"
          allow(vm).to receive_message_chain("metadata_link.href") { metadata_link }
          state = {
            vm: vm,
            env_metadata_key: "key"
          }
          expect(client).to receive(:invoke).with(
            :get, anything
          ).and_return metadata
          described_class.new(state, client).perform
          expect(state[:env]).to eq Yajl.load(metadata.value)
        end
      end
    end
  end
end
