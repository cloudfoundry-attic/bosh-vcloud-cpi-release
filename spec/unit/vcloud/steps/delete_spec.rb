require "spec_helper"

module VCloudCloud
  module Steps
    describe Delete do
      let(:remove_link) { "remove_link" }

      let(:client) do
        client = double("client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg }
        client
      end

      let(:vm) do
        vm = double("vm")
        vm.stub(:name) { "vm_name" }
        vm
      end

      describe ".perform" do
        it "delete entity" do
          vm.should_receive(:remove_link).with(false) { remove_link }
          client.should_receive(:invoke_and_wait).with(
            :delete, remove_link
          )
          state = { vm: vm }

          described_class.new(state, client).perform vm
        end

        it "force delete entity" do
          vm.should_receive(:remove_link).with(true) { remove_link }
          client.should_receive(:invoke_and_wait).with(
            :delete, remove_link
          )
          state = { vm: vm }

          described_class.new(state, client).perform(vm, true)
        end

        it "raises error when can't delete entity" do
          vm.should_receive(:remove_link).with(false) { nil }
          state = { vm: vm }

          expect {
            described_class.new(state, client).perform vm
          }.to raise_error /can't be removed/
        end

      end
    end
  end
end
