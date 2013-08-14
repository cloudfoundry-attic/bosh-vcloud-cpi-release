require "spec_helper"

module VCloudCloud
  module Steps
    describe EjectCatalogMedia do
      let(:client) do
        client = double("client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg }
        client.stub(:timed_loop) do |&block|
          while true do
            block.call
          end
        end
        client
      end

      let(:media) do
        media = double("media")
        media.stub(:href) { media_href }
        media.stub(:name) { media_name}
        media.stub(:entity) { media }
        media
      end

      let(:media_href) { "media_href" }
      let(:media_name) { "mymedia.iso" }

      let(:vm) do
        vm = double("vm")
        vm.stub(:name) { "vm name" }
        vm.stub(:eject_media_link) { eject_media_link }
        vm
      end

      let(:eject_media_link) { "eject_media_link" }

      describe ".perform" do
        it "return if media not exist" do
          client.should_receive(:catalog_item).with(
            :media, media_name, anything) { nil }
          state = { vm: vm}

          described_class.new(state, client).perform media_name
        end

        it "eject media" do
          client.should_receive(:catalog_item).with(
            :media, media_name, anything) { media }
          state = { vm: vm }
          client.should_receive(:wait_entity) { |arg| arg }
          client.should_receive(:invoke_and_wait).once.ordered.with(
            :post, eject_media_link, anything
          )
          client.should_receive(:resolve_link) { media }
          task = double("task")
          media.should_receive(:running_tasks).once { [ task ] }
          media.should_receive(:running_tasks).once { [] }

          described_class.new(state, client).perform media_name
        end
      end
    end
  end
end
