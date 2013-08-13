require 'spec_helper'

module VCloudCloud
  module Steps

    describe UploadCatalogMedia do

      let(:name) { "media_name" }
      let(:iso) { "media_iso" }
      let(:type) { "media_type" }
      let(:storage_profile) { "media_storage_profile" }

      let(:media_file_size) { "1000" }
      let(:media_file) do
        file = double("media_file")
        file.stub_chain(:stat, :size) { media_file_size }
        file
      end

      let(:file_upload_link_href) { "http://upload/file" }
      let(:incomplete_file) do
        file = double("media_incomplete_file")
        file.stub_chain(:upload_link, :href) { file_upload_link_href }
        file
      end

      let(:media) do
        media = double("media")
        media.stub_chain(:incomplete_files, :pop) { incomplete_file }
        media
      end

      let(:upload_media_link) { "http://upload_media_link" }
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) do |arg|
          arg
        end
        client.stub_chain(:vdc, :upload_media_link) { upload_media_link }
        client.stub(:invoke) do |method, href, params|
          media if href == upload_media_link
        end
        client
      end

      it "invokes the step" do
        File.should_receive(:new).once.with(iso, 'rb') { media_file }

        media_file.should_receive(:stat).once
        media.should_receive(:incomplete_files).once
        incomplete_file.should_receive(:upload_link).once

        client.should_receive(:invoke).once.ordered.with(:post, upload_media_link, kind_of(Hash))
        client.should_receive(:upload_stream).once.ordered.with(file_upload_link_href, media_file_size, media_file)
        client.should_receive(:reload).once.ordered.with(media)

        Transaction.perform("upload_catalog_media", client) do |s|
          s.next described_class, name, iso, type, storage_profile
          s.state[:media].should be media
        end
      end
    end

  end
end
