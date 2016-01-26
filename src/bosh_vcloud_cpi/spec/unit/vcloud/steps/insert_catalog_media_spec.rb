require 'spec_helper'

module VCloudCloud
  module Steps

    describe InsertCatalogMedia do

      let(:task_list) do
        task_list = double("media task list")
        task_list
      end

      let(:media_href_value) {"http://media/href"}
      let(:media_name) {"media"}
      let(:media) do
        media = double("vcloud media")
        allow(media).to receive(:name) {media_name}
        allow(media).to receive(:href) {media_href_value}
        allow(media).to receive(:running_tasks) {task_list}
        allow(media).to receive(:prerunning_tasks) { [] }
        media
      end

      let(:insert_media_link_value) {"http://vm/insert_media"}
      let(:vm) do
        vm = double("vcloud vm")
        allow(vm).to receive(:name) {"vcloud vm"}
        allow(vm).to receive(:insert_media_link) {insert_media_link_value}
        vm
      end

      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) do |arg|
          arg
        end
        allow(client).to receive(:media) do |arg|
          [media, nil] if arg == media_name
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
        it "invokes the method on media with running tasks" do
          # setup the test data
          state = {:vm => vm}

          #configure mock expectations
          expect(client).to receive(:media).once.ordered.with(media_name)
          expect(media).to receive(:href).once.ordered
          expect(client).to receive(:timed_loop).once.ordered
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(client).to receive(:reload).once.ordered.with(vm)
          expect(media).to receive(:running_tasks).once.ordered
          expect(task_list).to receive(:empty?).once.ordered {false}
          expect(client).to receive(:wait_entity).once.ordered
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(client).to receive(:reload).once.ordered.with(vm)
          expect(media).to receive(:running_tasks).once.ordered
          expect(task_list).to receive(:empty?).once.ordered {true}
          expect(media).to receive(:prerunning_tasks).once.ordered
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:post, insert_media_link_value, kind_of(Hash))
          expect(client).to receive(:reload).once.ordered.with(vm)

          #run the test
          step = described_class.new state, client
          step.perform media_name
        end

        it "invokes the method on media with no running tasks" do
          # setup the test data
          state = {:vm => vm}

          #configure mock expectations
          expect(client).to receive(:media).once.ordered.with(media_name)
          expect(media).to receive(:href).once.ordered
          expect(client).to receive(:timed_loop).once.ordered
          expect(client).to receive(:reload).once.ordered.with(media)
          expect(client).to receive(:reload).once.ordered.with(vm)
          expect(media).to receive(:running_tasks).once.ordered
          expect(task_list).to receive(:empty?).once.ordered {true}
          expect(client).to receive(:invoke_and_wait).once.ordered.with(:post, insert_media_link_value, kind_of(Hash))
          expect(client).to receive(:reload).once.ordered.with(vm)

          #run the test
          step = described_class.new state, client
          step.perform media_name
        end

        it "raises exception due to timeout" do
          # setup the test data
          state = {:vm => vm}

          #configure mock expectations
          expect(client).to receive(:media).once.ordered.with(media_name)
          expect(media).to receive(:href).once.ordered
          expect(client).to receive(:timed_loop).once.ordered {raise TimeoutError}

          #run the test
          step = described_class.new state, client
          expect{step.perform media_name}.to raise_exception TimeoutError
        end
      end
    end
  end
end
