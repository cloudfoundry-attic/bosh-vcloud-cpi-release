require 'spec_helper'

module VCloudCloud
  module Steps
    describe UploadTemplateFiles do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |obj| obj }
        expect(client).to receive(:invoke).with(:put, ovf_upload_link, anything)
        expect(client).to receive(:upload_stream).with(vmdk_upload_link,vmdk_file_size, anything)
        allow(client).to receive(:wait_entity)
        client
      end

      let(:template) do
        template = double("vapp_template")
        expect(template).to receive(:files).twice.ordered { [ ovf_file, vmdk_file ] }
        expect(template).to receive(:files).twice.ordered { [] }
        expect(template).to receive(:incomplete_files) { [ ovf_file, vmdk_file ] }
        template
      end

      let(:ovf_file) do
        ovf_file = double("ovf")
        allow(ovf_file).to receive(:name) { stemcell_ovf }
        allow(ovf_file).to receive_message_chain("upload_link.href") { ovf_upload_link }
        allow(ovf_file).to receive(:read) { "file_content" }
        ovf_file
      end

      let(:vmdk_file) do
        vmdk_file = double("vmdk")
        vmdk_name = "demo.vmdk"
        allow(vmdk_file).to receive(:name) { vmdk_name }
        allow(vmdk_file).to receive_message_chain("upload_link.href") { vmdk_upload_link }
        allow(vmdk_file).to receive(:size) { vmdk_file_size }
        allow(vmdk_file).to receive(:path) { File.join(stemcell_dir, vmdk_name)}
        vmdk_file
      end

      let(:stemcell_dir) { "/tmp" }
      let(:stemcell_ovf) { "demo.ovf" }
      let(:ovf_upload_link) { "ovf_upload_link" }
      let(:vmdk_upload_link) { "vmdk_upload_link" }
      let(:vmdk_file_size) { 10 }

      it "should upload template files" do
        expect(File).to receive(:new) { ovf_file }
        expect(File).to receive(:new) { vmdk_file }

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
