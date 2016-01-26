require 'spec_helper'

module VCloudCloud
  module Steps

    describe UploadMediaFiles do

      let(:iso) { "media_iso" }

      let(:media_file_size) { "1000" }
      let(:media_file) do
        file = double("media_file")
        allow(file).to receive_message_chain(:stat, :size) { media_file_size }
        file
      end

      let(:file_upload_link_href) { "http://upload/file" }
      let(:incomplete_file) do
        file = double("media_incomplete_file")
        allow(file).to receive_message_chain(:upload_link, :href) { file_upload_link_href }
        file
      end

      let(:media) do
        media = double("media")
        allow(media).to receive_message_chain(:incomplete_files, :pop) { incomplete_file }
        media
      end

      let(:upload_media_link) { "http://upload_media_link" }
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) do |arg|
          arg
        end
        allow(client).to receive_message_chain(:vdc, :upload_media_link) { upload_media_link }
        allow(client).to receive(:invoke) do |method, href, params|
          media if href == upload_media_link
        end
        client
      end

      it "invokes the step" do
        # setup test data
        state = {:media => media}

        # configure mock expectations
        expect(File).to receive(:new).once.ordered.with(iso, 'rb') { media_file }
        expect(media).to receive(:incomplete_files).once.ordered
        expect(incomplete_file).to receive(:upload_link).once.ordered
        expect(media_file).to receive(:stat).once.ordered
        expect(client).to receive(:upload_stream).once.ordered.with(file_upload_link_href, media_file_size, media_file)
        expect(client).to receive(:reload).once.ordered.with(media)

        # run test
        described_class.new(state, client).perform iso
        expect(state[:media]).to be media
      end
    end

  end
end
