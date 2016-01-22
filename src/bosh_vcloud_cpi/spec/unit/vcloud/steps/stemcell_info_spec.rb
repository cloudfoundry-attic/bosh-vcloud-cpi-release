require "spec_helper"

module VCloudCloud
  module Steps
    describe StemcellInfo do
      let(:client) do
        client = double("vcloud client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client
      end
      let(:stemcell) { VCloudCloud::Test.spec_asset("valid_stemcell.tgz") }

      it "update stemcell info" do
        Transaction.perform("reboot", client) do |s|
          s.state[:stemcell_ovf].should be_nil
          s.next described_class, stemcell
          s.state[:stemcell_ovf].should_not be_nil
        end
      end

      it "should evoke clean up when failed" do
        stemcell = "/tmp/not_exist"
        FileUtils.should_receive(:remove_entry_secure)

        expect {
          Transaction.perform("reboot", client) do |s|
            s.state[:stemcell_ovf].should be_nil
            s.next described_class, stemcell
            s.state[:stemcell_ovf].should be_nil
          end
        }.to raise_error /Invalid stemcell image: .*#{stemcell}.*/
      end
    end
  end
end
