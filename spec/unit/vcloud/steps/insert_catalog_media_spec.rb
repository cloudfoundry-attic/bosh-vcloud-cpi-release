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
        media.stub(:name) {media_name}
        media.stub(:href) {media_href_value}
        media.stub(:running_tasks) {task_list}
        media
      end

      let(:insert_media_link_value) {"http://vm/insert_media"}
      let(:vm) do
        vm = double("vcloud vm")
        vm.stub(:name) {"vcloud vm"}
        vm.stub(:insert_media_link) {insert_media_link_value}
        vm
      end

      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) do |arg|
          arg
        end
        client.stub(:media) do |arg|
          [media, nil] if arg == media_name
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
        it "invokes the method on media with running tasks" do
          # setup the test data
          state = {:vm => vm}

          #configure mock expectations
          client.should_receive(:media).once.ordered.with(media_name)
          media.should_receive(:href).once.ordered
          client.should_receive(:timed_loop).once.ordered
          client.should_receive(:reload).once.ordered.with(media)
          client.should_receive(:reload).once.ordered.with(vm)
          media.should_receive(:running_tasks).once.ordered
          task_list.should_receive(:empty?).once.ordered {false}
          client.should_receive(:wait_entity).once.ordered
          client.should_receive(:reload).once.ordered.with(media)
          client.should_receive(:reload).once.ordered.with(vm)
          media.should_receive(:running_tasks).once.ordered
          task_list.should_receive(:empty?).once.ordered {true}
          client.should_receive(:invoke_and_wait).once.ordered.with(:post, insert_media_link_value, kind_of(Hash))
          client.should_receive(:reload).once.ordered.with(vm)

          #run the test
          step = described_class.new state, client
          step.perform media_name
        end

        it "invokes the method on media with no running tasks" do
          # setup the test data
          state = {:vm => vm}

          #configure mock expectations
          client.should_receive(:media).once.ordered.with(media_name)
          media.should_receive(:href).once.ordered
          client.should_receive(:timed_loop).once.ordered
          client.should_receive(:reload).once.ordered.with(media)
          client.should_receive(:reload).once.ordered.with(vm)
          media.should_receive(:running_tasks).once.ordered
          task_list.should_receive(:empty?).once.ordered {true}
          client.should_receive(:invoke_and_wait).once.ordered.with(:post, insert_media_link_value, kind_of(Hash))
          client.should_receive(:reload).once.ordered.with(vm)

          #run the test
          step = described_class.new state, client
          step.perform media_name
        end

        it "raises exception due to timeout" do
          # setup the test data
          state = {:vm => vm}

          #configure mock expectations
          client.should_receive(:media).once.ordered.with(media_name)
          media.should_receive(:href).once.ordered
          client.should_receive(:timed_loop).once.ordered {raise TimeoutError}

          #run the test
          step = described_class.new state, client
          expect{step.perform media_name}.to raise_exception TimeoutError
        end
      end
    end
  end
end