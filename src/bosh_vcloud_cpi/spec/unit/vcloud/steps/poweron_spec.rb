require "spec_helper"

module VCloudCloud
  module Steps
    describe PowerOn do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) { |arg| arg}
        client
      end

      let(:vm) do
        vm = double("vm")
        allow(vm).to receive(:power_on_link) { poweron_link }
        allow(vm).to receive(:name) { "name" }
        vm
      end

      let(:poweron_link) { "poweron_link" }

      let(:poweroff_link) { "poweroff_link" }
      let(:poweron_target) { "poweron_target" }
      let(:entity) {
        entity = double("entity")
        allow(entity).to receive(:name) { "name" }
        entity
      }

      describe ".perform" do
        it "performs poweron" do
          allow(vm).to receive('[]').with("status") {
            VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
          }
          state = { vm: vm }
          expect(client).to receive(:invoke_and_wait).with(
            :post, poweron_link
          )

          described_class.new(state, client).perform(:vm)
        end

        it "return when vm is already poweron" do
          allow(vm).to receive('[]').with("status") {
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
            expect(client).to_not receive(:reload)
            expect(client).to_not receive(:invoke_and_wait)

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

            allow(entity).to receive('[]').with("status") {
              VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
            }

            # configure mock expectations
            expect(client).to receive(:reload).with(poweron_target).and_return(entity)
            expect(entity).to receive(:power_off_link).and_return(poweroff_link)
            expect(client).to receive(:invoke_and_wait).once.ordered.with(:post, poweroff_link)

            # run the test
            described_class.new(state, client).rollback
          end

          it "skip powering off the VM if it's already powered off." do
            #setup the test data
            state = {
                :poweron_target => poweron_target
            }

            allow(entity).to receive('[]').with("status") {
              VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
            }

            # configure mock expectations
            expect(client).to receive(:reload).with(poweron_target).and_return(entity)
            expect(entity).to_not receive(:power_off_link)
            expect(client).to_not receive(:invoke_and_wait)

            # run the test
            described_class.new(state, client).rollback
          end

          it "skip powering off the VM if it's already powered on by other step." do
            #setup the test data
            state = {}

            allow(entity).to receive('[]').with("status") {
              VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
            }

            # configure mock expectations
            expect(client).to_not receive(:reload)
            expect(client).to_not receive(:invoke_and_wait)

            # run the test
            described_class.new(state, client).rollback
          end
        end
      end
    end
  end
end
