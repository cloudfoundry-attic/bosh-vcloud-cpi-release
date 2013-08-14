require 'spec_helper'

module VCloudCloud
  module Steps

    describe CreateTemplate do

      let(:template_name) {"my template"}

      let(:template) do
        app = double("vapp template")
        app
      end

      let(:vdc_upload_link_value) {"http://vdc/upload_link"}
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub_chain(:vdc, :upload_link) {vdc_upload_link_value}
        client.stub(:invoke) {template}
        client.stub(:reload) do |arg|
          arg
        end
        client
      end

      describe ".perform" do
        it "creates a vapp template" do
          # setup test data
          state = {}

          # configure mock expectations
          client.should_receive(:vdc).once.ordered
          client.should_receive(:invoke).once.ordered.with(:post, vdc_upload_link_value, kind_of(Hash))

          # run test
          step = described_class.new state, client
          step.perform template_name
          expect(state[:vapp_template]).to be template
        end
      end

      describe ".rollback" do
        it "does nothing" do
          # setup test data
          state = {}

          # configure mock expectations
          template.should_not_receive(:cancel_link)
          template.should_not_receive(:remove_link)
          client.should_not_receive(:invoke)
          client.should_not_receive(:reload)
          client.should_not_receive(:invoke_and_wait)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "cancels and removes template" do
          # setup test data
          cancel_link = "http://vapp/cancel"
          remove_link = "http://vapp/remove"
          state = {:vapp_template => template}

          # configure mock expectations
          template.should_receive(:cancel_link).twice.ordered {cancel_link}
          client.should_receive(:invoke).once.ordered.with(:post, cancel_link)
          client.should_receive(:reload).once.ordered.with(template)
          template.should_receive(:remove_link).twice.ordered {remove_link}
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "removes template" do
          # setup test data
          remove_link = "http://vapp/remove"
          state = {:vapp_template => template}

          # configure mock expectations
          template.should_receive(:cancel_link).once.ordered {nil}
          client.should_not_receive(:invoke)
          client.should_not_receive(:reload)
          template.should_receive(:remove_link).twice.ordered {remove_link}
          client.should_receive(:invoke_and_wait).once.ordered.with(:delete, remove_link)

          # run test
          step = described_class.new state, client
          step.rollback
        end

        it "cancels template" do
          # setup test data
          cancel_link = "http://vapp/cancel"
          state = {:vapp_template => template}

          # configure mock expectations
          template.should_receive(:cancel_link).twice.ordered {cancel_link}
          client.should_receive(:invoke).once.ordered.with(:post, cancel_link)
          client.should_receive(:reload).once.ordered.with(template)
          template.should_receive(:remove_link).once.ordered
          client.should_not_receive(:invoke_and_wait)

          # run test
          step = described_class.new state, client
          step.rollback
        end
      end
    end

  end
end
