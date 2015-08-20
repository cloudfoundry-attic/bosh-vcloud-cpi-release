require 'spec_helper'

module VCloudCloud
  module Steps

    describe DeleteCatalogMedia do

      let(:media_name) {"my media"}
      let(:media_delete_link) {"http://media/delete"}
      let(:media) do
        media = double("media")
        media.stub(:name) {media_name}
        media.stub(:delete_link) {media_delete_link}
        media
      end

      let(:catalog_item) do
        item = double("catalog item")
        item.stub(:entity) {media}
        item
      end

      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:catalog_item) do |tag, name, type |
          catalog_item if tag == :media && name == media_name && type == VCloudSdk::Xml::MEDIA_TYPE[:MEDIA]
        end
        client.stub(:resolve_link) do |arg|
          arg
        end
        client.stub(:timed_loop) do |&block|
          while true do
            block.call
          end
        end
        client.stub(:reload) do |arg|
          arg
        end
        client.stub(:wait_entity) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "deletes media with running tasks" do
          # setup test values
          state = {}

          # configure mock expectations
          client.should_receive(:catalog_item).once.ordered.with(:media, media_name, anything)
          catalog_item.should_receive(:entity).once.ordered
          client.should_receive(:resolve_link).once.ordered.with(media)
          client.should_receive(:timed_loop).once.ordered
          client.should_receive(:reload).once.ordered.with(media)
          media.should_receive(:running_tasks).once.ordered {["task1"]}
          client.should_receive(:wait_entity).once.ordered.with(media)
          client.should_receive(:reload).once.ordered.with(media)
          media.should_receive(:running_tasks).once.ordered {[]}
          media.should_receive(:delete_link).once.ordered
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)
          client.should_receive(:invoke).once.ordered.with(:delete, catalog_item)

          # run test
          described_class.new(state, client).perform media_name
        end

        it "deletes media without running tasks" do
          # setup test values
          state = {}

          # configure mock expectations
          client.should_receive(:catalog_item).once.ordered.with(:media, media_name, anything)
          catalog_item.should_receive(:entity).once.ordered
          client.should_receive(:resolve_link).once.ordered.with(media)
          client.should_receive(:timed_loop).once.ordered
          client.should_receive(:reload).once.ordered.with(media)
          media.should_receive(:running_tasks).once.ordered {[]}
          media.should_receive(:delete_link).once.ordered
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)
          client.should_receive(:invoke).once.ordered.with(:delete, catalog_item)

          # run test
          described_class.new(state, client).perform media_name
        end

        it "return when media is missing" do
          # setup test values
          missing_media = "missing media"
          state = {}

          # configure mock expectations
          client.should_receive(:catalog_item).once.ordered.with(:media, missing_media, anything)
          catalog_item.should_not_receive(:entity)
          client.should_not_receive(:resolve_link)

          # run test
          described_class.new(state, client).perform missing_media
        end
      end

    end

  end
end
