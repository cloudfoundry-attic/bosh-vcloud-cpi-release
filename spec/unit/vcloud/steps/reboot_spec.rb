require 'spec_helper'

module VCloudCloud
  module Steps
    describe Reboot do
      it "evoke reboot" do
        client = double("vcloud client")
        vm = double("vm entity")
        client.stub(:reload) { vm }
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        reboot_link = "link"
        vm.should_receive(:reboot_link) { reboot_link }
        client.should_receive(:invoke_and_wait).with(:post, reboot_link)

        Transaction.perform("reboot", client) do |s|
          s.state[:vm] = vm
          s.next described_class, :vm
        end
      end
    end
  end
end
