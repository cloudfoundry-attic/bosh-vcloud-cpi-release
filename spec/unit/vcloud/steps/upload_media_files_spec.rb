require 'spec_helper'

module VCloudCloud
  module Steps

    describe UploadMediaFiles do

      let(:iso) { "media_iso" }

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
        # setup test data
        state = {:media => media}

        # configure mock expectations
        File.should_receive(:new).once.ordered.with(iso, 'rb') { media_file }
        media.should_receive(:incomplete_files).once.ordered
        incomplete_file.should_receive(:upload_link).once.ordered
        media_file.should_receive(:stat).once.ordered
        client.should_receive(:upload_stream).once.ordered.with(file_upload_link_href, media_file_size, media_file)
        client.should_receive(:reload).once.ordered.with(media)

        # run test
        described_class.new(state, client).perform iso
        expect(state[:media]).to be media
      end
    end

  end
end
