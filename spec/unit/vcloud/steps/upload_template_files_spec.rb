require 'spec_helper'

module VCloudCloud
  module Steps
    describe UploadTemplateFiles do
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |obj| obj }
        client.should_receive(:invoke).with(:put, ovf_upload_link, anything)
        client.should_receive(:upload_stream).with(vmdk_upload_link,vmdk_file_size, anything)
        client.stub(:wait_entity)
        client
      end

      let(:template) do
        template = double("vapp_template")
        template.should_receive(:files).twice.ordered { [ ovf_file, vmdk_file ] }
        template.should_receive(:files).twice.ordered { [] }
        template.should_receive(:incomplete_files) { [ ovf_file, vmdk_file ] }
        template
      end

      let(:ovf_file) do
        ovf_file = double("ovf")
        ovf_file.stub(:name) { stemcell_ovf }
        ovf_file.stub_chain("upload_link.href") { ovf_upload_link }
        ovf_file.stub(:read) { "file_content" }
        ovf_file
      end

      let(:vmdk_file) do
        vmdk_file = double("vmdk")
        vmdk_name = "demo.vmdk"
        vmdk_file.stub(:name) { vmdk_name }
        vmdk_file.stub_chain("upload_link.href") { vmdk_upload_link }
        vmdk_file.stub(:size) { vmdk_file_size }
        vmdk_file.stub(:path) { File.join(stemcell_dir, vmdk_name)}
        vmdk_file
      end

      let(:stemcell_dir) { "/tmp" }
      let(:stemcell_ovf) { "demo.ovf" }
      let(:ovf_upload_link) { "ovf_upload_link" }
      let(:vmdk_upload_link) { "vmdk_upload_link" }
      let(:vmdk_file_size) { 10 }

      it "should upload template files" do
        File.should_receive(:new) { ovf_file }
        File.should_receive(:new) { vmdk_file }

        Transaction.perform("upload_template_files", client) do |s|
          s.state[:stemcell_dir] = stemcell_dir
          s.state[:stemcell_ovf] = stemcell_ovf
          s.state[:vapp_template] = template
          s.next described_class
        end
      end
    end
  end
end
