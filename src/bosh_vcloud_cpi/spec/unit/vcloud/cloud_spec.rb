require "spec_helper"
require "yaml"

module VCloudCloud
  class Cloud
    attr_accessor :client
  end

  describe Cloud do
    shared_context "base" do
      before do
        subject.client = client
        allow(subject).to receive(:steps).and_yield(trx).and_return(state)
        allow(Bosh::Retryable).to receive(:new).and_return(retryable)
        allow(retryable).to receive(:retryer).and_yield(:tries, :error)
      end

      let(:retryable) { double('Bosh::Retryable') }

      let(:trx) do
        trx = double("Transaction")
        allow(trx).to receive(:state) { state }
        trx
      end

      let(:client) do
        client = double("client")
        allow(client).to receive(:catalog_name).with(:vapp).and_return "my_bosh_catalog"
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        allow(client).to receive(:resolve_entity).with(vm_id).and_return vm
        allow(client).to receive(:resolve_link).with(vm_link).and_return vm
        allow(client).to receive(:resolve_entity).with(vapp_id).and_return vapp
        allow(client).to receive(:resolve_link).with(vapp_link).and_return vapp
        allow(client).to receive(:resolve_entity).with(disk_id).and_return disk
        allow(client).to receive(:reload) { |obj| obj }
        allow(client).to receive_message_chain('vdc.storage_profiles')
        allow(client).to receive(:flush_cache)
        client
      end

      let(:state) { {} }
      let(:vapp_id) { "vapp_id" }
      let(:vapp_link) { "vapp_link" }
      let(:vapp) { double(vapp_id) }

      let(:vm_id) { "vm_id" }
      let(:vm_link) { "vm_link" }
      let(:vm) do
        vm = {}
        allow(vm).to receive(:container_vapp_link) { vapp_link }
        allow(vm).to receive(:agent_id) {"fake-agent-id"}
        allow(vm).to receive(:agent_id=) { }
        vm
      end

      let(:disk_id) { "disk_id" }
      let(:disk) { double(disk_id)}
    end

    let(:cloud_properties) { VCloudCloud::Test::director_cloud_properties }
    let(:subject) { described_class.new cloud_properties }

    describe "#new" do
      it "should validate initial arguments" do
        props = Marshal.load(Marshal.dump(cloud_properties))
        props.delete 'vcds'
        expect {described_class.new props}.to raise_error ArgumentError

        props = Marshal.load(Marshal.dump(cloud_properties))
        props['vcds'][0].delete 'entities'
        expect {described_class.new props}.to raise_error ArgumentError
      end
    end

    describe ".create_stemcell" do
      include_context "base"
      before do
        allow(Kernel).to receive(:sleep)
      end

      it "uses a transaction with the expected steps to create a stemcell" do
        image = "stemcell_name"
        result = "urn"
        template = double('template')
        catalog_item = double('catalog_item')
        expect(trx).to receive(:next).once.ordered.with(Steps::StemcellInfo, image)
        expect(trx).to receive(:next).once.ordered.with(Steps::AddCatalog, "my_bosh_catalog")
        expect(trx).to receive(:next).once.ordered.with(Steps::CreateTemplate, anything, :vapp)
        expect(trx).to receive(:next).once.ordered.with(Steps::UploadTemplateFiles)
        allow(trx).to receive_message_chain('state.[]').with(:vapp_template).and_return template
        allow(trx).to receive_message_chain('state.[]').with(:catalog_item).and_return catalog_item
        allow(catalog_item).to receive(:urn).and_return result

        expect(subject.create_stemcell(image, nil)).to eq result
      end

      it "retry after upload stemcell Timeout" do
        image = "stemcell_name"
        result = "urn"
        template = double('template')
        catalog_item = double('catalog_item')
        allow(Bosh::Retryable).to receive(:new).and_call_original
        expect(trx).to receive(:next).once.ordered.with(Steps::StemcellInfo, image)
        expect(trx).to receive(:next).once.ordered.with(Steps::AddCatalog, "my_bosh_catalog")
        expect(trx).to receive(:next).once.ordered.with(Steps::CreateTemplate, anything, :vapp)
        times_called = 0
        expect(trx).to receive(:next).twice.ordered.with(Steps::UploadTemplateFiles) do
          times_called += 1
          if times_called == 1
            raise Timeout::Error
          end
          'fake_result'
        end
        allow(trx).to receive_message_chain('state.[]').with(:vapp_template).and_return template
        allow(trx).to receive_message_chain('state.[]').with(:catalog_item).and_return catalog_item
        allow(catalog_item).to receive(:urn).and_return result
        expect(subject.create_stemcell(image, nil)).to eq result
      end

      it "raise Timeout error after retry count exceeded" do
        image = "stemcell_name"
        result = "urn"
        template = double('template')
        catalog_item = double('catalog_item')
        allow(Bosh::Retryable).to receive(:new).and_call_original
        expect(trx).to receive(:next).once.ordered.with(Steps::StemcellInfo, image)
        expect(trx).to receive(:next).once.ordered.with(Steps::AddCatalog, "my_bosh_catalog")
        expect(trx).to receive(:next).once.ordered.with(Steps::CreateTemplate, anything, :vapp)
        allow(trx).to receive_message_chain(:next).with(Steps::UploadTemplateFiles).and_raise Timeout::Error
        allow(trx).to receive_message_chain('state.[]').with(:vapp_template).and_return template
        allow(trx).to receive_message_chain('state.[]').with(:catalog_item).and_return catalog_item
        expect { expect(subject.create_stemcell(image, nil)).to eq result }.to raise_error(Timeout::Error)
      end
    end

    describe ".delete_stemcell" do
      include_context "base"

      it "evoke delete vapp and delete catalog" do
        vapp_remove_link = "remove_link"
        catalog_link = "catalog_link"
        entity_link = "vapp_entity"
        expect(vapp).to receive(:remove_link) { vapp_remove_link }
        expect(vapp).to receive(:href) { catalog_link }
        expect(vapp).to receive(:entity) { vapp_link }
        # we allow failed delete vapp task
        expect(client).to receive(:wait_entity).with(vapp, true)
        expect(client).to receive(:invoke).with(:delete, vapp_remove_link)
        expect(client).to receive(:invoke).with(:delete, catalog_link)

        subject.delete_stemcell vapp_id
      end

      context 'when the stemcell does not exist' do
        it 'continues if the vapp_id is not found' do
          allow(client).to receive(:resolve_entity).with(vapp_id).and_return nil
          expect { subject.delete_stemcell(vapp_id)}.to_not raise_error
        end

        it 'continues if ObjectNotFoundError is raised' do
          allow(client).to receive(:resolve_entity).with(vapp_id).and_raise ObjectNotFoundError.new
          expect { subject.delete_stemcell(vapp_id) }.to_not raise_error
        end

        it 'continues if RestClient::Forbidden is raised' do
          allow(client).to receive(:resolve_entity).with(vapp_id).and_raise RestClient::Forbidden.new
          expect { subject.delete_stemcell(vapp_id) }.to_not raise_error
        end
      end
    end

    describe ".create_vm" do
      include_context "base"

      it "create vm and vapp" do
        agent_id = "agent_id"
        catalog_vapp_id = "catalog_vapp_id"
        resource_pool = double("resource pool")
        networks = double("networks")
        allow(vm).to receive_message_chain("hardware_section.hard_disks").and_return []
        allow(vapp).to receive_message_chain("vms.[]").and_return vm
        result = "urn"
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Instantiate,
          catalog_vapp_id, anything, anything, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::CreateOrUpdateAgentEnv, anything, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::PowerOn, anything)
        allow(trx).to receive_message_chain("state.[]").with(:vapp).and_return vapp
        allow(trx).to receive_message_chain("state.[]").with(:vm).and_return vm
        allow(vm).to receive(:urn).and_return result
        allow(trx).to receive_message_chain("state.[]=")
        allow(subject).to receive(:reconfigure_vm)
        allow(subject).to receive(:save_agent_env)

        expect(subject.create_vm(agent_id, catalog_vapp_id, resource_pool, nil))
          .to eq result
      end

      it "should reuse existing vapp" do

        vapp_name = "existing_vapp"
        vm_name = "created_vm"
        environment = {"vapp" => vapp_name}
        agent_id = "agent_id"
        catalog_vapp_id = "catalog_vapp_id"
        vm_link = "vm_link"
        resource_pool = double("resource pool")
        networks = double("networks")
        existing_vapp = double("existing_vapp")
        allow(existing_vapp).to receive(:name).and_return vapp_name
        expect(existing_vapp).to receive(:vms).and_return [vm]
        allow(vm).to receive_message_chain("hardware_section.hard_disks").and_return []
        allow(vm).to receive(:href) { vm_link }
        allow(vm).to receive(:name) { vm_name }
        allow(vapp).to receive(:name) { vapp_id }
        allow(vapp).to receive_message_chain("vms.[]").and_return vm
        result = "urn"
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Instantiate,
          catalog_vapp_id,
          anything,
          anything,
          anything,
          anything)
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Recompose, vapp_name, existing_vapp, vm)
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Delete, vapp, anything)
        expect(trx).to receive(:next).once.ordered.with(
          Steps::CreateOrUpdateAgentEnv,
          networks,
          anything,
          anything )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::PowerOn, anything)
        allow(trx).to receive_message_chain("state.[]").with(:vapp).and_return vapp
        allow(trx).to receive_message_chain("state.[]").with(:vm).and_return vm
        allow(vm).to receive(:urn).and_return result
        allow(trx).to receive_message_chain("state.[]=")
        allow(client).to receive(:wait_entity)
        expect(client).to receive(:vapp_by_name).with(vapp_name).
          and_return(existing_vapp)
        allow(subject).to receive(:reconfigure_vm)
        allow(subject).to receive(:save_agent_env)

        expect(subject.create_vm(agent_id, catalog_vapp_id, resource_pool,networks, nil, environment))
          .to eq result
      end
    end

    describe ".reboot_vm" do
      include_context "base"

      before do
        state["vm"] = vm
      end

      it "reboot vm when it's power on" do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Reboot, anything )

        subject.reboot_vm vm_id
      end

      it 'Force a hard-reboot when failed to perform a soft-reboot' do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
        exceptionMsg = 'Reboot Failed!'
        expect(trx).to receive(:next).once.ordered.with(
            Steps::Reboot, anything ).and_raise(exceptionMsg)
        expect(trx).to receive(:next).once.ordered.with(
            Steps::PowerOff, anything, anything )
        expect(trx).to receive(:next).once.ordered.with(
            Steps::PowerOn, anything )

        begin
          subject.reboot_vm vm_id
        rescue => ex
          expect(ex.to_s).to eq exceptionMsg
        end
      end

      it "power on a vm when it's powered off" do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
        expect(trx).to receive(:next).once.ordered.with(
          Steps::PowerOn, anything )

        subject.reboot_vm vm_id
      end

      it "discard suspend and reboot vm" do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
        expect(trx).to receive(:next).once.ordered.with(
          Steps::DiscardSuspendedState, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::PowerOn, anything
        )

        subject.reboot_vm vm_id
      end
    end

    describe ".has_vm?" do
      include_context "base"

      it "tells whether vm exists" do
        expect(vm).to receive(:type).and_return(VCloudSdk::Xml::MEDIA_TYPE[:VM])
        expect(vm).to receive(:type).and_return(VCloudSdk::Xml::MEDIA_TYPE[:VAPP])
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
        expect(client).to receive(:resolve_entity).twice.and_return(vm)
        expect(client).to receive(:resolve_entity).and_raise RestClient::Exception.new
        expect(client).to receive(:resolve_entity).and_raise ObjectNotFoundError.new

        expect(subject.has_vm?(vm_id)).to be true
        expect(subject.has_vm?(vm_id)).to be false
        expect(subject.has_vm?(vm_id)).to be false
        expect(subject.has_vm?(vm_id)).to be false
      end
    end

    describe ".delete_vm" do

      before(:each) do
        allow(vapp).to receive(:name)
      end

      include_context "base"

      it "delete vapp if the vapp name matches vm.agent_id" do
        allow(vm).to receive(:name)
        allow(vapp).to receive(:vms) { [vm] }
        expect(vapp).to receive(:name).and_return("fake-agent-id")
        expect(trx).to receive(:next).twice.ordered.with(
          Steps::PowerOff, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Undeploy, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Delete, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::DeleteCatalogMedia, anything
        )

        subject.delete_vm vm_id
      end

      it "should not delete vapp if the vapp name does match vm.agent_id" do
        allow(vm).to receive(:name)
        allow(vapp).to receive(:vms) { [vm] }
        expect(vapp).to receive(:name).and_return("fake-agent-id-2")
        expect(trx).to receive(:next).once.ordered.with(
          Steps::PowerOff, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Undeploy, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Delete, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::DeleteCatalogMedia, anything
        )

        subject.delete_vm vm_id
      end

      it "delete vm" do
        vm2 = double("vm2")
        allow(vm).to receive(:name)
        allow(vapp).to receive(:vms) { [vm , vm2] }
        expect(trx).to receive(:next).once.ordered.with(
          Steps::PowerOff, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Undeploy, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Delete, anything, anything
        )
        expect(trx).to receive(:next).once.ordered.with(
          Steps::DeleteCatalogMedia, anything
        )

        subject.delete_vm vm_id
      end

      context 'when the vm does not exist' do
        it 'continues if ObjectNotFoundError is raised' do
          allow(client).to receive(:resolve_entity).and_raise ObjectNotFoundError.new
          expect{ subject.delete_vm vm_id }.to_not raise_error
        end

        it 'continues if RestClient::Forbidden is raised' do
          allow(client).to receive(:resolve_entity).and_raise RestClient::Forbidden.new
          expect{ subject.delete_vm vm_id }.to_not raise_error
        end

        it 'continues if RestClient::Forbidden is raised in deletion stage' do
          allow(client).to receive(:resolve_entity).and_return vm
          allow(trx).to receive(:next).once.ordered.with(
              Steps::PowerOff, anything, anything
          ).and_raise RestClient::Forbidden.new
          expect{ subject.delete_vm vm_id }.to_not raise_error
        end
      end
    end

    describe ".configure_networks" do
      include_context "base"

      it "config network" do
        vm_name = "vm_name"
        network = {
          'cloud_properties' => { 'name' => "demo_network"}
        }
        networks = { demo_network: network }

        expect {subject.configure_networks(vm_id, networks)}
          .to raise_error Bosh::Clouds::NotSupported
      end
    end

    describe ".create_disk" do
      include_context "base"

      it "create a disk" do
        size_mb = 10
        result = "disk_urn"
        expect(trx).to receive(:next).once.ordered.with(
          Steps::CreateDisk, anything, size_mb, nil, nil
        )
        allow(trx).to receive_message_chain("state.[]").with(:disk).and_return disk
        allow(disk).to receive(:urn).and_return result

        expect(subject.create_disk(size_mb, {})).to eq result
      end

      it "create disk with vm locality" do
        size_mb = 10
        vm_locality = [ vm ]
        result = "disk_urn"
        expect(client).to receive(:resolve_entity).with(vm_locality).
          and_return vm
        expect(trx).to receive(:next).once.ordered
          .with(Steps::CreateDisk, anything, size_mb, vm, nil)
        allow(trx).to receive_message_chain("state.[]").with(:disk).and_return disk
        allow(disk).to receive(:urn).and_return result

        expect(subject.create_disk(size_mb, {}, vm_locality)).to eq result
      end
    end

    describe ".attach_disk" do
      include_context "base"

      it "attach a disk to vm" do
        state[:vm] = vm
        state[:env] = {}
        expect(trx).to receive(:next).once.ordered.with(
          Steps::AttachDetachDisk, :attach)
        expect(trx).to receive(:next).once.ordered.with(
          Steps::LoadAgentEnv )
        allow(subject).to receive(:save_agent_env)

        ephemeral_disk = double("ephemeral_disk")
        expect(ephemeral_disk).to receive(:disk_id).and_return("1")

        allow(vm).to receive_message_chain("hardware_section.hard_disks").and_return( [], [ ephemeral_disk ])

        subject.attach_disk(vm_id, disk_id)

        expect(state[:env]['disks']['persistent'][disk_id]).to eq "1"
      end
    end

    describe ".detach_disk" do
      include_context "base"

      it "detach a disk from vm" do
        expect(vm).to receive(:find_attached_disk).and_return true
        allow(vm).to receive(:[]).with('status').and_return(
          VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s )
        state[:vm] = vm
        state[:env] = {}
        expect(trx).to receive(:next).once.ordered.with(
          Steps::DiscardSuspendedState, anything)
        expect(trx).to receive(:next).once.ordered.with(
          Steps::AttachDetachDisk, :detach)
        expect(trx).to receive(:next).once.ordered.with(
          Steps::LoadAgentEnv)
        allow(subject).to receive(:save_agent_env)

        subject.detach_disk(vm_id, disk_id)
      end

      it "ignore a disk not belongs to vm" do
        expect(vm).to receive(:find_attached_disk).and_return nil
        state = {:vm => vm, :env => {}}
        allow(trx).to receive("state").and_return state

        subject.detach_disk(vm_id, disk_id)
      end
    end

    describe ".delete_disk" do
      include_context "base"

      before do
        client = double("client")
        allow(client).to receive(:logger) { Bosh::Clouds::Config.logger }
      end

      it "delete a disk" do
        expect(trx).to receive(:next).once.ordered.with(
          Steps::Delete, disk, true)
        allow(client).to receive(:resolve_entity).with(disk_id).and_return disk
        subject.delete_disk(disk_id)
      end

      context 'when the disk does not exist' do
        it 'continues if ObjectNotFoundError is raised' do
          allow(client).to receive(:resolve_entity).with(disk_id).and_raise ObjectNotFoundError.new
          expect { subject.delete_disk(disk_id) }.to_not raise_error
        end

        it 'continues if RestClient::Forbidden if raised' do
          allow(client).to receive(:resolve_entity).with(disk_id).and_raise RestClient::Forbidden.new
          expect { subject.delete_disk(disk_id) }.to_not raise_error
        end

        it 'continues if RestClient::Forbidden if raised in deletion stage' do
          allow(client).to receive(:resolve_entity).with(disk_id).and_return vm
          allow(trx).to receive(:next).once.ordered.with(
              Steps::Delete, anything, anything
          ).and_raise RestClient::Forbidden.new
          expect { subject.delete_disk(disk_id) }.to_not raise_error
        end
      end
    end

    describe ".save_agent_env" do
      include_context "base"

      it 'performs the expected steps' do

        allow(trx).to receive_message_chain("state.[]").with(:vm).and_return vm
        allow(trx).to receive_message_chain("state.[]").with(:iso).and_return 'iso'
        allow(trx).to receive_message_chain("state.[]").with(:media).and_return 'media'

        allow(vm).to receive(:name).and_return 'name'
        allow(client).to receive(:catalog_name).with(:media)

        expect(trx).to receive(:next).once.ordered.with(Steps::SaveAgentEnv)
        expect(trx).to receive(:next).once.ordered.with(Steps::AddCatalog, anything)
        expect(trx).to receive(:next).once.ordered.with(Steps::EjectCatalogMedia, anything)
        expect(trx).to receive(:next).once.ordered.with(Steps::DeleteCatalogMedia, anything)
        expect(trx).to receive(:next).once.ordered.with(Steps::CreateMedia, anything, anything, anything, anything)
        expect(trx).to receive(:next).once.ordered.with(Steps::UploadMediaFiles, anything)
        expect(trx).to receive(:next).once.ordered.with(Steps::AddCatalogItem, anything, anything)
        expect(trx).to receive(:next).once.ordered.with(Steps::InsertCatalogMedia, anything)

        t = trx
        subject.instance_eval{save_agent_env(t)}
      end
    end

    describe '.calculate_vm_cloud_properties' do
      include_context "base"

      it 'maps cloud agnostic properties to vcloud specific properties' do
        input = {'ram'=> 123, 'cpu'=> 1, 'ephemeral_disk_size'=> 1}
        expect(subject.calculate_vm_cloud_properties(input)).to eq({
          'ram' => 123,
          'cpu' => 1,
          'disk' => 1
        })
      end

      it 'returns an error if any fields are missing' do
        input = {}
        expect{ subject.calculate_vm_cloud_properties(input) }.to raise_error("Missing VM cloud properties: 'ram', 'cpu', 'ephemeral_disk_size'")
      end

      it 'returns an error if a single field is missing' do
        input = {'ram' => 123, 'cpu' => 1}
        expect{ subject.calculate_vm_cloud_properties(input) }.to raise_error("Missing VM cloud properties: 'ephemeral_disk_size'")
      end
    end

    describe "methods that raise NotImplemented" do
      describe ".current_vm_id" do
        include_context "base"

        it "returns Bosh::Cloud::NotImplemented" do
          expect { subject.current_vm_id }.to raise_error(Bosh::Clouds::NotImplemented)
        end
      end

      describe ".delete_snapshot" do
        include_context "base"

        it "returns Bosh::Cloud::NotImplemented" do
          expect { subject.delete_snapshot("fake-snapshot-id") }.to raise_error(Bosh::Clouds::NotImplemented)
        end
      end

      describe ".has_disk?" do
        include_context "base"

        it "returns Bosh::Cloud::NotImplemented" do
          expect { subject.has_disk?("fake-disk-id") }.to raise_error(Bosh::Clouds::NotImplemented)
        end
      end

      describe ".get_disks" do
        include_context "base"

        it "returns Bosh::Cloud::NotImplemented" do
          expect { subject.get_disks("fake-vm-id") }.to raise_error(Bosh::Clouds::NotImplemented)
        end
      end

      describe ".set_vm_metadata" do
        include_context "base"

        it "returns Bosh::Cloud::NotImplemented" do
          data = {}
          expect { subject.set_vm_metadata("fake-vm-id", data) }.to raise_error(Bosh::Clouds::NotImplemented)
        end
      end

      describe ".snapshot_disk" do
        include_context "base"

        it "returns Bosh::Cloud::NotImplemented" do
          expect { subject.snapshot_disk("fake-disk-id", {}) }.to raise_error(Bosh::Clouds::NotImplemented)
        end
      end
    end
  end
end
