require 'spec_helper'

module VCloudCloud
  module Steps

    describe SaveAgentEnv do

      let(:env_metadata_key_value) {"env_metadata"}
      let(:meta_data_link_href) {"http://meta_data/link/href"}
      let(:tmp_dir) {"/tmp/eerrtds"}

      let(:env) do
        env = double("vcloud env")
        env.stub(:inspect) {"env data"}
        env
      end

      let(:save_file) do
        file = double("env save file")
        file.stub(:write) do |data|
          data
        end
      end

      let(:vm) do
        vm = double("vcloud vm")
        vm.stub_chain(:metadata_link, :href) {meta_data_link_href}
        vm.stub(:urn) {"urn:vm:id"}
        vm
      end

      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "invokes method successfully" do
          #setup the test input
          state = {:vm => vm, :env_metadata_key => env_metadata_key_value}

          #configure mock expectations
          client.should_receive(:reload).once.ordered.with(vm)
          Yajl::Encoder.should_receive(:encode).once do |env|
            env.to_s
          end
          Dir.should_receive(:mktmpdir).once { tmp_dir }
          File.should_receive(:open).once.ordered.with("#{tmp_dir}/env", "w") {save_file}
          described_class.any_instance.should_receive(:`) {"Running genisoimage command"}
          allow_message_expectations_on_nil
          $?.should_receive(:success?).once {true}
          client.should_receive(:invoke_and_wait).once.ordered.with(:put, "#{meta_data_link_href}/#{env_metadata_key_value}", kind_of(Hash))
          client.should_receive(:reload).once.ordered.with(vm)

          #execute the test
          step = described_class.new state, client
          step.perform
          expect(state[:iso]).to eql "#{tmp_dir}/env.iso"
        end

        it "raises exception due to failed cmd" do
          #setup the test input
          state = {:vm => vm, :env_metadata_key => env_metadata_key_value}

          #configure mock expectations
          client.should_receive(:reload).once.ordered.with(vm)
          Yajl::Encoder.should_receive(:encode).once do |env|
            env.to_s
          end
          Dir.should_receive(:mktmpdir).once { tmp_dir }
          File.should_receive(:open).once.ordered.with("#{tmp_dir}/env", "w") {save_file}
          described_class.any_instance.should_receive(:`) {"Failed to run genisoimage command"}
          allow_message_expectations_on_nil
          $?.should_receive(:success?).once {false}
          $?.stub(:exitstatus) {"2"}

          #execute the test
          step = described_class.new state, client
          expect{step.perform}.to raise_exception RuntimeError
          expect(state[:iso]).to be_nil
        end
      end

      describe ".cleanup" do
        it ".deletes temp folder" do
          #setup the test input
          state = {:tmpdir => tmp_dir}

          #configure mock expectations
          FileUtils.should_receive(:remove_entry_secure).once.with(tmp_dir)

          #execute the test
          step = described_class.new state, client
          step.cleanup
        end

        it ".has no temp folder to delte" do
          #setup the test input
          state = {}

          # configure mocks
          FileUtils.stub(:remove_entry_secure) {raise "Should not call remove on empty tmpdir"}

          # execute the test
          step = described_class.new state, client
          step.cleanup
        end
      end

    end

  end
end

