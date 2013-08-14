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
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub_chain(:vdc, :add_disk_link) {vdc_add_disk_link_value}
        client.stub(:invoke) {disk}
        client.stub(:wait_entity) do |arg|
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
          client.should_receive(:invoke).once.ordered.with(:post, vdc_add_disk_link_value, kind_of(Hash))
          client.should_receive(:wait_entity).once.ordered.with(disk)

          # run test
          described_class.new(state, client).perform disk_name, disk_size, vm
          expect(state[:disk]).to be disk
        end

        it "creates disk without locality" do
          # setup test data
          state = {}

          # configure mock expectations
          client.should_receive(:invoke).once.ordered.with(:post, vdc_add_disk_link_value, kind_of(Hash))
          client.should_receive(:wait_entity).once.ordered.with(disk)

          # run test
          described_class.new(state, client).perform disk_name, disk_size, nil
          expect(state[:disk]).to be disk
        end
      end

    end

  end
end
