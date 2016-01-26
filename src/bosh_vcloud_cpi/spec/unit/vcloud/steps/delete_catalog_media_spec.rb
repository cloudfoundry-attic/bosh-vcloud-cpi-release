require 'spec_helper'

module VCloudCloud
  module Steps

    describe DeleteCatalogMedia do

      let(:media_name) {"my media"}
      let(:media_delete_link) {"http://media/delete"}
      let(:media) do
        media = double("media")
        allow(media).to receive(:name) {media_name}
        allow(media).to receive(:delete_link) {media_delete_link}
        media
      end

      let(:catalog_item) do
        item = double("catalog item")
        allow(item).to receive(:entity) {media}
        item
      end

      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:catalog_item) do |tag, name, type |
          catalog_item if tag == :media && name == media_name && type == VCloudSdk::Xml::MEDIA_TYPE[:MEDIA]
        end
        allow(client).to receive(:resolve_link) do |arg|
          arg
        end
        allow(client).to receive(:timed_loop) do |&block|
          while true do
            block.call
          end
        end
        allow(client).to receive(:reload) do |arg|
          arg
        end
        allow(client).to receive(:wait_entity) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "deletes media with running tasks" do
          # setup test values
          state = {}

          # configure mock expectations
          expect(client).to receive(:catalog_item).once.ordered.with(:media, media_name, anything)
          expect(catalog_item).to receive(:entity).once.ordered
          expect(client).to receive(:resolve_link).once.ordered.with(media)
          expect(client).to receive(:timed_loop).once.ordered
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(media).to receive(:running_tasks).once.ordered {["task1"]}
          expect(client).to receive(:wait_entity).once.ordered.with(media)
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(media).to receive(:running_tasks).once.ordered {[]}
          expect(media).to receive(:delete_link).once.ordered
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)
          expect(client).to receive(:invoke).once.ordered.with(:delete, catalog_item)

          # run test
          described_class.new(state, client).perform media_name
        end

        it "deletes media without running tasks" do
          # setup test values
          state = {}

          # configure mock expectations
          expect(client).to receive(:catalog_item).once.ordered.with(:media, media_name, anything)
          expect(catalog_item).to receive(:entity).once.ordered
          expect(client).to receive(:resolve_link).once.ordered.with(media)
          expect(client).to receive(:timed_loop).once.ordered
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(media).to receive(:running_tasks).once.ordered {[]}
          expect(media).to receive(:delete_link).once.ordered
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:delete, media_delete_link)
          expect(client).to receive(:invoke).once.ordered.with(:delete, catalog_item)

          # run test
          described_class.new(state, client).perform media_name
        end

        it "return when media is missing" do
          # setup test values
          missing_media = "missing media"
          state = {}

          # configure mock expectations
          expect(client).to receive(:catalog_item).once.ordered.with(:media, missing_media, anything)
          expect(catalog_item).to_not receive(:entity)
          expect(client).to_not receive(:resolve_link)

          # run test
          described_class.new(state, client).perform missing_media
        end
      end

    end

  end
end
