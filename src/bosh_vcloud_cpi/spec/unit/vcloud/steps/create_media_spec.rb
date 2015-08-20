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
        file.stub_chain(:stat, :size) { media_file_size }
        file
      end

      let(:media_delete_link) {"http://media/delete"}
      let(:media) do
        media = double("media")
        media.stub(:delete_link) {media_delete_link}
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
        client.stub(:timed_loop) do |&block|
          while true do
            block.call
          end
        end
        client.stub(:wait_entity) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "invokes method" do
          # setup test data
          state = {}

          # configure mock expectations
          File.should_receive(:new).once.ordered.with(iso, 'rb') { media_file }
          media_file.should_receive(:stat).once.ordered
          client.should_receive(:vdc).once.ordered
          client.should_receive(:invoke).once.ordered.with(:post, upload_media_link, kind_of(Hash))

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
          client.should_receive(:timed_loop).once.ordered
          client.should_receive(:reload).once.ordered.with(media)
          media.should_receive(:running_tasks).once.ordered {["task 1"]}
          client.should_receive(:wait_entity).once.ordered.with(media)
          client.should_receive(:reload).once.ordered.with(media)
          media.should_receive(:running_tasks).once.ordered {[]}
          media.should_receive(:delete_link).once.ordered
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:media)).to be_false
        end

        it "rolls back media without running tasks" do
          # setup test data
          state = {:media => media}

          # configure mock expectations
          client.should_receive(:timed_loop).once.ordered
          client.should_receive(:reload).once.ordered.with(media)
          media.should_receive(:running_tasks).once.ordered {[]}
          media.should_receive(:delete_link).once.ordered
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)

          # run the test
          described_class.new(state, client).rollback
          expect(state.key?(:media)).to be_false
        end
      end
    end

  end
end