require 'spec_helper'

module VCloudCloud
  module Steps

    describe AddNetworks do

      let(:ip_s1) do
        ip_s = double("ip_scope")
        allow(ip_s).to receive(:is_inherited?) { false }
        allow(ip_s).to receive(:gateway) { "192.168.1.1" }
        allow(ip_s).to receive(:netmask) { "255.255.255.1" }
        allow(ip_s).to receive(:start_address) { nil }
        allow(ip_s).to receive(:end_address) { nil }
        ip_s
      end

      let(:n1) do
        n = double("network 1")
        allow(n).to receive(:name) { "network 1" }
        allow(n).to receive(:href) { "http://n1" }
        allow(n).to receive(:ip_scope) { ip_s1 }
        n
      end

      let(:ip_s2) do
        ip_s = double("ip_scope")
        allow(ip_s).to receive(:is_inherited?) { false }
        allow(ip_s).to receive(:gateway) { "192.168.1.1" }
        allow(ip_s).to receive(:netmask) { "255.255.255.1" }
        allow(ip_s).to receive(:start_address) { "192.168.1.50" }
        allow(ip_s).to receive(:end_address) { "192.168.1.100" }
        ip_s
      end

      let(:n2) do
        n = double("network 2")
        allow(n).to receive(:name) { "network 2" }
        allow(n).to receive(:href) { "http://n2" }
        allow(n).to receive(:ip_scope) { ip_s2 }
        n
      end

      let(:net_conf) do
        net_conf = double("network config")
        allow(net_conf).to receive(:add_network_config) do |arg|
          arg
        end
        net_conf
      end

      let(:vapp) do
        vapp = double("vapp")
        allow(vapp).to receive(:network_config_section) { net_conf }
        vapp
      end

      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:reload) do |arg|
          arg
        end
        allow(client).to receive_message_chain(:vdc, :available_networks) { [n1, n2] }
        allow(client).to receive_message_chain(:vdc, :name) {"vcloud data center"}
        allow(client).to receive(:invoke_and_wait)
        client
      end

      it "invokes step successfully" do
        expect(n1).to receive(:name).exactly(5).times
        expect(n1).to receive(:ip_scope).once
        expect(n1).to receive(:href).once

        expect(n2).to receive(:name).exactly(4).times
        expect(n2).to receive(:ip_scope).once
        expect(n2).to receive(:href).once

        expect(net_conf).to receive(:add_network_config).twice

        expect(vapp).to receive(:network_config_section).exactly(6).times

        expect(client).to receive(:vdc).once

        expect(client).to receive(:reload).once.ordered.with(vapp)
        expect(client).to receive(:reload).once.ordered.with(n1)
        expect(client).to receive(:reload).once.ordered.with(n2)
        expect(client).to receive(:reload).once.ordered.with(vapp)

        expect(client).to receive(:invoke_and_wait).twice.with(:put, net_conf, kind_of(Hash))

        Transaction.perform("add_networks", client) do |s|
          s.state[:vapp] = vapp
          s.next described_class, [n1, n2].map() {|n| n.name}
        end
      end

      it "raises exception due to missing network" do
        expect(n1).to receive(:name).once
        expect(n2).to receive(:name).once
        expect(client).to receive(:vdc).twice
        expect(client).to receive(:reload).once.ordered.with(vapp)

        expect do
          Transaction.perform("add_networks", client) do |s|
            s.state[:vapp] = vapp
            s.next described_class, ["test"]
          end
        end.to raise_exception RuntimeError
      end

    end

  end
end