require 'spec_helper'

module VCloudCloud
  module Steps
    describe Reboot do
      it "evoke reboot" do
        client = double("vcloud client")
        vm = double("vm entity")
        allow(client).to receive(:reload) { vm }
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        reboot_link = "link"
        expect(vm).to receive(:reboot_link) { reboot_link }
        expect(client).to receive(:invoke_and_wait).with(:post, reboot_link)

        Transaction.perform("reboot", client) do |s|
          s.state[:vm] = vm
          s.next described_class, :vm
        end
      end
    end
  end
end
