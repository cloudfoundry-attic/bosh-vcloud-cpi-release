require 'spec_helper'

module VCloudCloud
  module Steps

    describe AttachDetachDisk do
      before(:each) do
        @client = double("vcloud client").as_null_object
        @client.stub(:reload) do |arg|
          arg
        end
        @client.stub(:invoke_and_wait) do |method, link, params|
          params[:payload].href
        end

        @vm = double("vm entity").as_null_object
        @attach_disk_link = "attach_link"
        @vm.stub(:attach_disk_link) do |arg|
          @attach_disk_link
        end

        @disk_href = "disk_href"
        @disk = double("vm disk").as_null_object
        @disk.stub(:href) { @disk_href }
      end

      it "invokes attach_detach_disk" do
        @vm.should_receive(:attach_disk_link).once

        @disk.should_receive(:href).once

        @client.should_receive(:invoke_and_wait).with(:post, @attach_disk_link, kind_of(Hash))
        @client.should_receive(:reload).once.ordered.with(@vm)
        @client.should_receive(:reload).once.ordered.with(@disk)

        Transaction.perform("attach", @client) do |s|
          s.state[:vm] = @vm
          s.state[:disk] = @disk
          s.next described_class, :attach
        end
      end
    end

  end
end
