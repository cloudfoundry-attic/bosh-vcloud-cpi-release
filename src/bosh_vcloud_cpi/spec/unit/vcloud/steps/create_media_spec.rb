require 'spec_helper'

module VCloudCloud
  module Steps

    describe CreateMedia do

      let(:name) { "media_name" }
      let(:iso) { "media_iso" }
      let(:type) { "media_type" }
      let(:storage_profile) { "media_storage_profile" }

      let(:media_file_size) { "1000" }
      let(:media_file) do
        file = double("media_file")
        allow(file).to receive_message_chain(:stat, :size) { media_file_size }
        file
      end

      let(:media_delete_link) {"http://media/delete"}
      let(:media) do
        media = double("media")
        allow(media).to receive(:delete_link) {media_delete_link}
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
        allow(client).to receive(:timed_loop) do |&block|
          while true do
            block.call
          end
        end
        allow(client).to receive(:wait_entity) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "invokes method" do
          # setup test data
          state = {}

          # configure mock expectations
          expect(File).to receive(:new).once.ordered.with(iso, 'rb') { media_file }
          expect(media_file).to receive(:stat).once.ordered
          expect(client).to receive(:vdc).once.ordered
          expect(client).to receive(:invoke).once.ordered.with(:post, upload_media_link, kind_of(Hash))

          # run the test
          described_class.new(state, client).perform name, iso, type, storage_profile
          expect(state[:media]).to be media
        end
      end

      describe ".rollback" do
        it "rolls back media with running tasks" do
          # setup test data
          state = {:media => media}

          # configure mock expectations
          expect(client).to receive(:timed_loop).once.ordered
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(media).to receive(:running_tasks).once.ordered {["task 1"]}
          expect(client).to receive(:wait_entity).once.ordered.with(media)
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(media).to receive(:running_tasks).once.ordered {[]}
          expect(media).to receive(:delete_link).once.ordered
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:media)).to be false
        end

        it "rolls back media without running tasks" do
          # setup test data
          state = {:media => media}

          # configure mock expectations
          expect(client).to receive(:timed_loop).once.ordered
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(media).to receive(:running_tasks).once.ordered {[]}
          expect(media).to receive(:delete_link).once.ordered
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:media)).to be false
        end
      end
    end

  end
end