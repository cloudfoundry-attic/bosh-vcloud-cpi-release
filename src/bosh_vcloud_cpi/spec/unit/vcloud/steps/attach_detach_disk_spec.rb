require 'spec_helper'

module VCloudCloud
  module Steps

    describe AttachDetachDisk do
      before(:each) do
        @client = double("vcloud client").as_null_object
        allow(@client).to receive(:reload) do |arg|
          arg
        end
        allow(@client).to receive(:invoke_and_wait) do |method, link, params|
          params[:payload].href
        end

        @vm = double("vm entity").as_null_object
        @attach_disk_link = "attach_link"
        allow(@vm).to receive(:attach_disk_link) do |arg|
          @attach_disk_link
        end

        @disk_href = "disk_href"
        @disk = double("vm disk").as_null_object
        allow(@disk).to receive(:href) { @disk_href }
      end

      it "invokes attach_detach_disk" do
        expect(@vm).to receive(:attach_disk_link).once

        expect(@disk).to receive(:href).once

        expect(@client).to receive(:invoke_and_wait).with(:post, @attach_disk_link, kind_of(Hash))
        expect(@client).to receive(:reload).once.ordered.with(@vm)
        expect(@client).to receive(:reload).once.ordered.with(@disk)

        Transaction.perform("attach", @client) do |s|
          s.state[:vm] = @vm
          s.state[:disk] = @disk
          s.next described_class, :attach
        end
      end
    end

  end
end
