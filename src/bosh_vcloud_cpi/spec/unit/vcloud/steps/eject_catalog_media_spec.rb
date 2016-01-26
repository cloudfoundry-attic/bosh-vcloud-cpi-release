require "spec_helper"

module VCloudCloud
  module Steps
    describe EjectCatalogMedia do
      let(:client) do
        client = double("client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg }
        allow(client).to receive(:timed_loop) do |&block|
          while true do
            block.call
          end
        end
        client
      end

      let(:media) do
        media = double("media")
        allow(media).to receive(:href) { media_href }
        allow(media).to receive(:name) { media_name}
        allow(media).to receive(:entity) { media }
        media
      end

      let(:media_href) { "media_href" }
      let(:media_name) { "mymedia.iso" }

      let(:vm) do
        vm = double("vm")
        allow(vm).to receive(:name) { "vm name" }
        allow(vm).to receive(:eject_media_link) { eject_media_link }
        vm
      end

      let(:eject_media_link) { "eject_media_link" }

      describe ".perform" do
        it "return if media not exist" do
          expect(client).to receive(:catalog_item).with(
            :media, media_name, anything) { nil }
          state = { vm: vm}

          described_class.new(state, client).perform media_name
        end

        it "eject media" do
          expect(client).to receive(:catalog_item).with(
            :media, media_name, anything) { media }
          state = { vm: vm }
          expect(client).to receive(:wait_entity) { |arg| arg }
          expect(client).to receive(:invoke_and_wait).once.ordered.with(
            :post, eject_media_link, anything
          )
          expect(client).to receive(:resolve_link) { media }
          task = double("task")
          expect(media).to receive(:running_tasks).once { [ task ] }
          expect(media).to receive(:running_tasks).once { [] }

          described_class.new(state, client).perform media_name
        end
      end
    end
  end
end
