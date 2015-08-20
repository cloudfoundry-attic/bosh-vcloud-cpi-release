require "spec_helper"

module VCloudCloud
  module Steps
    describe PowerOn do
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) { |arg| arg}
        client
      end

      let(:vm) do
        vm = double("vm")
        vm.stub(:power_on_link) { poweron_link }
        vm.stub(:name) { "name" }
        vm
      end

      let(:poweron_link) { "poweron_link" }

      let(:poweroff_link) { "poweroff_link" }
      let(:poweron_target) { "poweron_target" }
      let(:entity) {
        entity = double("entity")
        entity.stub(:name) { "name" }
        entity
      }

      describe ".perform" do
        it "performs poweron" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
          }
          state = { vm: vm }
          client.should_receive(:invoke_and_wait).with(
            :post, poweron_link
          )

          described_class.new(state, client).perform(:vm)
        end

        it "return when vm is already poweron" do
          vm.stub('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
          }
          state = { vm: vm }

          described_class.new(state, client).perform(:vm)
        end
      end

      describe ".rollback" do
        context "rollback is not called" do
          it "does nothing" do
            # setup test data
            state = {}

            # configure mock expectations
            client.should_not_receive(:reload)
            client.should_not_receive(:invoke_and_wait)

            # run test
            step = described_class.new state, client
            step.rollback
          end
        end

        context "rollback is called" do
          it "powers off the VM" do
            #setup the test data
            state = {
                :poweron_target => poweron_target
            }

            entity.stub('[]').with("status") {
              VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
            }

            # configure mock expectations
            client.should_receive(:reload).with(poweron_target).and_return(entity)
            entity.should_receive(:power_off_link).and_return(poweroff_link)
            client.should_receive(:invoke_and_wait).once.ordered.with(:post, poweroff_link)

            # run the test
            described_class.new(state, client).rollback
          end

          it "skip powering off the VM if it's already powered off." do
            #setup the test data
            state = {
                :poweron_target => poweron_target
            }

            entity.stub('[]').with("status") {
              VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
            }

            # configure mock expectations
            client.should_receive(:reload).with(poweron_target).and_return(entity)
            entity.should_not_receive(:power_off_link)
            client.should_not_receive(:invoke_and_wait)

            # run the test
            described_class.new(state, client).rollback
          end

          it "skip powering off the VM if it's already powered on by other step." do
            #setup the test data
            state = {}

            entity.stub('[]').with("status") {
              VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
            }

            # configure mock expectations
            client.should_not_receive(:reload)
            client.should_not_receive(:invoke_and_wait)

            # run the test
            described_class.new(state, client).rollback
          end
        end
      end
    end
  end
end
