require 'spec_helper'

module VCloudCloud
  module Steps

    describe AddNetworks do

      let(:ip_s1) do
        ip_s = double("ip_scope")
        ip_s.stub(:is_inherited?) { false }
        ip_s.stub(:gateway) { "192.168.1.1" }
        ip_s.stub(:netmask) { "255.255.255.1" }
        ip_s.stub(:start_address) { nil }
        ip_s.stub(:end_address) { nil }
        ip_s
      end

      let(:n1) do
        n = double("network 1")
        n.stub(:name) { "network 1" }
        n.stub(:href) { "http://n1" }
        n.stub(:ip_scope) { ip_s1 }
        n
      end

      let(:ip_s2) do
        ip_s = double("ip_scope")
        ip_s.stub(:is_inherited?) { false }
        ip_s.stub(:gateway) { "192.168.1.1" }
        ip_s.stub(:netmask) { "255.255.255.1" }
        ip_s.stub(:start_address) { "192.168.1.50" }
        ip_s.stub(:end_address) { "192.168.1.100" }
        ip_s
      end

      let(:n2) do
        n = double("network 2")
        n.stub(:name) { "network 2" }
        n.stub(:href) { "http://n2" }
        n.stub(:ip_scope) { ip_s2 }
        n
      end

      let(:net_conf) do
        net_conf = double("network config")
        net_conf.stub(:add_network_config) do |arg|
          arg
        end
        net_conf
      end

      let(:vapp) do
        vapp = double("vapp")
        vapp.stub(:network_config_section) { net_conf }
        vapp
      end

      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:reload) do |arg|
          arg
        end
        client.stub_chain(:vdc, :available_networks) { [n1, n2] }
        client.stub_chain(:vdc, :name) {"vcloud data center"}
        client.stub(:invoke_and_wait)
        client
      end

      it "invokes step successfully" do
        n1.should_receive(:name).exactly(5).times
        n1.should_receive(:ip_scope).once
        n1.should_receive(:href).once

        n2.should_receive(:name).exactly(4).times
        n2.should_receive(:ip_scope).once
        n2.should_receive(:href).once

        net_conf.should_receive(:add_network_config).twice

        vapp.should_receive(:network_config_section).exactly(6).times

        client.should_receive(:vdc).once

        client.should_receive(:reload).once.ordered.with(vapp)
        client.should_receive(:reload).once.ordered.with(n1)
        client.should_receive(:reload).once.ordered.with(n2)
        client.should_receive(:reload).once.ordered.with(vapp)

        client.should_receive(:invoke_and_wait).twice.with(:put, net_conf, kind_of(Hash))

        Transaction.perform("add_networks", client) do |s|
          s.state[:vapp] = vapp
          s.next described_class, [n1, n2].map() {|n| n.name}
        end
      end

      it "raises exception due to missing network" do
        n1.should_receive(:name).once
        n2.should_receive(:name).once
        client.should_receive(:vdc).twice
        client.should_receive(:reload).once.ordered.with(vapp)

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