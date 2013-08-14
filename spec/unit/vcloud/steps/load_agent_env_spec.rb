require "spec_helper"

module VCloudCloud
  module Steps
    describe LoadAgentEnv do
      let(:client) do
        client = double("client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg}
        client
      end

      let(:metadata) do
        metadata = double("metdadata")
        metadata.stub(:value) { '{"key":"value"}' }
        metadata
      end

      let(:vm) do
        vm = double("vm")
        vm
      end

      describe ".perform" do
        it "load agent environment" do
          metadata_link = "meta_data_link"
          vm.stub_chain("metadata_link.href") { metadata_link }
          state = {
            vm: vm,
            env_metadata_key: "key"
          }
          client.should_receive(:invoke).with(
            :get, anything
          ).and_return metadata
          described_class.new(state, client).perform
          state[:env].should == Yajl.load(metadata.value)
        end
      end
    end
  end
end
