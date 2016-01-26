require 'spec_helper'

module VCloudCloud
  module Steps

    describe CreateDisk do

      let(:disk_name) {"disk name"}
      let(:disk_size) {2}
      let(:disk) do
        disk = double("disk")
        disk
      end

      let(:vm) do
        vm = double("vm")
        vm
      end

      let(:vdc_add_disk_link_value) {"http://vdc/add/disk"}
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive_message_chain(:vdc, :add_disk_link) {vdc_add_disk_link_value}
        allow(client).to receive(:invoke) {disk}
        allow(client).to receive(:wait_entity) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "creates disk with locality" do
          # setup test data
          state = {}

          # configure mock expectations
          vm.as_null_object
          expect(client).to receive(:invoke).once.ordered.with(:post, vdc_add_disk_link_value, kind_of(Hash))
          expect(client).to receive(:wait_entity).once.ordered.with(disk)

          # run test
          described_class.new(state, client).perform disk_name, disk_size, vm, nil
          expect(state[:disk]).to be disk
        end

        it "creates disk without locality" do
          # setup test data
          state = {}

          # configure mock expectations
          expect(client).to receive(:invoke).once.ordered.with(:post, vdc_add_disk_link_value, kind_of(Hash))
          expect(client).to receive(:wait_entity).once.ordered.with(disk)

          # run test
          described_class.new(state, client).perform disk_name, disk_size, nil, nil
          expect(state[:disk]).to be disk
        end
      end

      describe ".rollback" do
        it "does nothing" do
          # setup test data
          state = {}

          # configure mock expectations
          expect(disk).to_not receive(:remove_link)
          expect(client).to_not receive(:invoke_and_wait)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "invokes the method" do
          #setup the test data
          state = {:disk => disk}
          remove_link = "http://disk/remove"

          # configure mock expectations
          expect(disk).to receive(:remove_link).once.ordered { remove_link }
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:disk)).to be false
        end
      end

    end

  end
end
