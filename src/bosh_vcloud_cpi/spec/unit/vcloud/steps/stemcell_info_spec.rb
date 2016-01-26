require "spec_helper"

module VCloudCloud
  module Steps
    describe StemcellInfo do
      let(:client) do
        client = double("vcloud client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        client
      end
      let(:stemcell) { VCloudCloud::Test.spec_asset("valid_stemcell.tgz") }

      it "update stemcell info" do
        Transaction.perform("reboot", client) do |s|
          expect(s.state[:stemcell_ovf]).to be_nil
          s.next described_class, stemcell
          expect(s.state[:stemcell_ovf]).to_not be_nil
        end
      end

      it "should evoke clean up when failed" do
        stemcell = "/tmp/not_exist"
        expect(FileUtils).to receive(:remove_entry_secure)

        expect {
          Transaction.perform("reboot", client) do |s|
            expect(s.state[:stemcell_ovf]).to be_nil
            s.next described_class, stemcell
            expect(s.state[:stemcell_ovf]).to be_nil
          end
        }.to raise_error /Invalid stemcell image: .*#{stemcell}.*/
      end
    end
  end
end
