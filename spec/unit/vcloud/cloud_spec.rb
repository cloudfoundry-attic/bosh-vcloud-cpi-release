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
        subject.stub(:steps).and_yield(trx).and_return(state)
        allow(Bosh::Retryable).to receive(:new).and_return(retryable)
        allow(retryable).to receive(:retryer).and_yield(:tries, :error)
      end

      let(:retryable) { double('Bosh::Retryable') }

      let(:trx) do
        trx = double("Transaction")
        trx.stub(:state) { state }
        trx
      end

      let(:client) do
        client = double("client")
        client.stub(:catalog_name).with(:vapp).and_return "my_bosh_catalog"
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:resolve_entity).with(vm_id).and_return vm
        client.stub(:resolve_link).with(vm_link).and_return vm
        client.stub(:resolve_entity).with(vapp_id).and_return vapp
        client.stub(:resolve_link).with(vapp_link).and_return vapp
        client.stub(:resolve_entity).with(disk_id).and_return disk
        client.stub(:reload) { |obj| obj }
        client.stub_chain('vdc.storage_profiles')
        client.stub(:flush_cache)
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
        vm.stub(:container_vapp_link) { vapp_link }
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
        Kernel.stub(:sleep)
      end

      it "uses a transaction with the expected steps to create a stemcell" do
        image = "stemcell_name"
        result = "urn"
        template = double('template')
        catalog_item = double('catalog_item')
        trx.should_receive(:next).once.ordered.with(Steps::StemcellInfo, image)
        trx.should_receive(:next).once.ordered.with(Steps::AddCatalog, "my_bosh_catalog")
        trx.should_receive(:next).once.ordered.with(Steps::CreateTemplate, anything, :vapp)
        trx.should_receive(:next).once.ordered.with(Steps::UploadTemplateFiles)
        trx.stub_chain('state.[]').with(:vapp_template).and_return template
        trx.stub_chain('state.[]').with(:catalog_item).and_return catalog_item
        catalog_item.stub(:urn).and_return result

        subject.create_stemcell(image, nil).should == result
      end

      it "retry after upload stemcell Timeout" do
        image = "stemcell_name"
        result = "urn"
        template = double('template')
        catalog_item = double('catalog_item')
        allow(Bosh::Retryable).to receive(:new).and_call_original
        trx.should_receive(:next).once.ordered.with(Steps::StemcellInfo, image)
        trx.should_receive(:next).once.ordered.with(Steps::AddCatalog, "my_bosh_catalog")
        trx.should_receive(:next).once.ordered.with(Steps::CreateTemplate, anything, :vapp)
        times_called = 0
        trx.should_receive(:next).twice.ordered.with(Steps::UploadTemplateFiles).and_return do
          times_called += 1
          if times_called == 1
            raise Timeout::Error
          end
          'fake_result'
        end
        trx.stub_chain('state.[]').with(:vapp_template).and_return template
        trx.stub_chain('state.[]').with(:catalog_item).and_return catalog_item
        catalog_item.stub(:urn).and_return result
        subject.create_stemcell(image, nil).should == result
      end

      it "raise Timeout error after retry count exceeded" do
        image = "stemcell_name"
        result = "urn"
        template = double('template')
        catalog_item = double('catalog_item')
        allow(Bosh::Retryable).to receive(:new).and_call_original
        trx.should_receive(:next).once.ordered.with(Steps::StemcellInfo, image)
        trx.should_receive(:next).once.ordered.with(Steps::AddCatalog, "my_bosh_catalog")
        trx.should_receive(:next).once.ordered.with(Steps::CreateTemplate, anything, :vapp)
        trx.stub_chain(:next).with(Steps::UploadTemplateFiles).and_raise Timeout::Error
        trx.stub_chain('state.[]').with(:vapp_template).and_return template
        trx.stub_chain('state.[]').with(:catalog_item).and_return catalog_item
        expect { subject.create_stemcell(image, nil).should == result }.to raise_error(Timeout::Error)
      end
    end

    describe ".delete_stemcell" do
      include_context "base"

      it "evoke delete vapp and delete catalog" do
        vapp_remove_link = "remove_link"
        catalog_link = "catalog_link"
        entity_link = "vapp_entity"
        vapp.should_receive(:remove_link) { vapp_remove_link }
        vapp.should_receive(:href) { catalog_link }
        vapp.should_receive(:entity) { vapp_link }
        # we allow failed delete vapp task
        client.should_receive(:wait_entity).with(vapp, true)
        client.should_receive(:invoke).with(:delete, vapp_remove_link)
        client.should_receive(:invoke).with(:delete, catalog_link)

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
        vm.stub_chain("hardware_section.hard_disks").and_return []
        vapp.stub_chain("vms.[]").and_return vm
        result = "urn"
        trx.should_receive(:next).once.ordered.with(
          Steps::Instantiate,
          catalog_vapp_id, anything, anything, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::CreateOrUpdateAgentEnv, anything, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOn, anything)
        trx.stub_chain("state.[]").with(:vapp).and_return vapp
        trx.stub_chain("state.[]").with(:vm).and_return vm
        vm.stub(:urn).and_return result
        trx.stub_chain("state.[]=")
        subject.stub(:reconfigure_vm)
        subject.stub(:save_agent_env)

        subject.create_vm(agent_id, catalog_vapp_id,
                          resource_pool, nil).
                          should == result
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
        existing_vapp.stub(:name).and_return vapp_name
        existing_vapp.should_receive(:vms).and_return [vm]
        vm.stub_chain("hardware_section.hard_disks").and_return []
        vm.stub(:href) { vm_link }
        vm.stub(:name) { vm_name }
        vapp.stub(:name) { vapp_id }
        vapp.stub_chain("vms.[]").and_return vm
        result = "urn"
        trx.should_receive(:next).once.ordered.with(
          Steps::Instantiate,
          catalog_vapp_id,
          anything,
          anything,
          anything,
          anything)
        trx.should_receive(:next).once.ordered.with(
          Steps::Recompose, vapp_name, existing_vapp, vm)
        trx.should_receive(:next).once.ordered.with(
          Steps::Delete, vapp, anything)
        trx.should_receive(:next).once.ordered.with(
          Steps::CreateOrUpdateAgentEnv,
          networks,
          anything,
          anything )
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOn, anything)
        trx.stub_chain("state.[]").with(:vapp).and_return vapp
        trx.stub_chain("state.[]").with(:vm).and_return vm
        vm.stub(:urn).and_return result
        trx.stub_chain("state.[]=")
        client.stub(:wait_entity)
        client.should_receive(:vapp_by_name).with(vapp_name).
          and_return(existing_vapp)
        subject.stub(:reconfigure_vm)
        subject.stub(:save_agent_env)

        subject.create_vm(agent_id, catalog_vapp_id,
                          resource_pool,networks, nil, environment).
                          should == result
      end
    end

    describe ".reboot_vm" do
      include_context "base"

      before do
        state["vm"] = vm
      end

      it "reboot vm when it's power on" do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
        trx.should_receive(:next).once.ordered.with(
          Steps::Reboot, anything )

        subject.reboot_vm vm_id
      end

      it 'Force a hard-reboot when failed to perform a soft-reboot' do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
        exceptionMsg = 'Reboot Failed!'
        trx.should_receive(:next).once.ordered.with(
            Steps::Reboot, anything ).and_raise(exceptionMsg)
        trx.should_receive(:next).once.ordered.with(
            Steps::PowerOff, anything, anything )
        trx.should_receive(:next).once.ordered.with(
            Steps::PowerOn, anything )

        begin
          subject.reboot_vm vm_id
        rescue => ex
          ex.to_s.should eq exceptionMsg
        end
      end

      it "power on a vm when it's powered off" do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOn, anything )

        subject.reboot_vm vm_id
      end

      it "discard suspend and reboot vm" do
        vm['status'] = VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
        trx.should_receive(:next).once.ordered.with(
          Steps::DiscardSuspendedState, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOn, anything
        )

        subject.reboot_vm vm_id
      end
    end

    describe ".has_vm?" do
      include_context "base"

      it "tells whether vm exists" do
        vm.should_receive(:type).and_return(VCloudSdk::Xml::MEDIA_TYPE[:VM])
        vm.should_receive(:type).and_return(VCloudSdk::Xml::MEDIA_TYPE[:VAPP])
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.should_receive(:resolve_entity).twice.and_return(vm)
        client.should_receive(:resolve_entity).and_raise RestClient::Exception.new
        client.should_receive(:resolve_entity).and_raise ObjectNotFoundError.new

        subject.has_vm?(vm_id).should == true
        subject.has_vm?(vm_id).should == false
        subject.has_vm?(vm_id).should == false
        subject.has_vm?(vm_id).should == false
      end
    end

    describe ".delete_vm" do
      include_context "base"

      it "delete vapp if there is only one vm" do
        vm.stub(:name)
        vapp.stub(:vms) { [vm] }
        trx.should_receive(:next).twice.ordered.with(
          Steps::PowerOff, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::Undeploy, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::Delete, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::DeleteCatalogMedia, anything
        )

        subject.delete_vm vm_id
      end

      it "delete vm" do
        vm2 = double("vm2")
        vm.stub(:name)
        vapp.stub(:vms) { [vm , vm2] }
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOff, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::Undeploy, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::Delete, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
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
        trx.should_receive(:next).once.ordered.with(
          Steps::CreateDisk, anything, size_mb, nil, nil
        )
        trx.stub_chain("state.[]").with(:disk).and_return disk
        disk.stub(:urn).and_return result

        subject.create_disk(size_mb, {}).should == result
      end

      it "create disk with vm locality" do
        size_mb = 10
        vm_locality = [ vm ]
        result = "disk_urn"
        client.should_receive(:resolve_entity).with(vm_locality).
          and_return vm
        trx.should_receive(:next).once.ordered.with(
          Steps::CreateDisk, anything, size_mb, vm, nil
        )
        trx.stub_chain("state.[]").with(:disk).and_return disk
        disk.stub(:urn).and_return result

        subject.create_disk(size_mb, {}, vm_locality).should == result
      end
    end

    describe ".attach_disk" do
      include_context "base"

      it "attach a disk to vm" do
        state[:vm] = vm
        state[:env] = {}
        trx.should_receive(:next).once.ordered.with(
          Steps::AttachDetachDisk, :attach)
        trx.should_receive(:next).once.ordered.with(
          Steps::LoadAgentEnv )
        subject.stub(:save_agent_env)

        ephemeral_disk = double("ephemeral_disk")
        ephemeral_disk.should_receive(:disk_id).and_return("1")

        vm.stub_chain("hardware_section.hard_disks").and_return( [], [ ephemeral_disk ])

        subject.attach_disk(vm_id, disk_id)

        state[:env]['disks']['persistent'][disk_id].should == "1"
      end
    end

    describe ".detach_disk" do
      include_context "base"

      it "detach a disk from vm" do
        vm.should_receive(:find_attached_disk).and_return true
        vm.stub(:[]).with('status').and_return(
          VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s )
        state[:vm] = vm
        state[:env] = {}
        trx.should_receive(:next).once.ordered.with(
          Steps::DiscardSuspendedState, anything)
        trx.should_receive(:next).once.ordered.with(
          Steps::AttachDetachDisk, :detach)
        trx.should_receive(:next).once.ordered.with(
          Steps::LoadAgentEnv)
        subject.stub(:save_agent_env)

        subject.detach_disk(vm_id, disk_id)
      end

      it "ignore a disk not belongs to vm" do
        vm.should_receive(:find_attached_disk).and_return nil
        state = {:vm => vm, :env => {}}
        trx.stub("state").and_return { state }

        subject.detach_disk(vm_id, disk_id)
      end
    end

    describe ".delete_disk" do
      include_context "base"

      before do
        client = double("client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
      end

      it "delete a disk" do
        trx.should_receive(:next).once.ordered.with(
          Steps::Delete, disk, true)
        client.stub(:resolve_entity).with(disk_id).and_return disk
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

        trx.stub_chain("state.[]").with(:vm).and_return vm
        trx.stub_chain("state.[]").with(:iso).and_return 'iso'
        trx.stub_chain("state.[]").with(:media).and_return 'media'

        vm.stub(:name).and_return 'name'
        client.stub(:catalog_name).with(:media)

        trx.should_receive(:next).once.ordered.with(Steps::SaveAgentEnv)
        trx.should_receive(:next).once.ordered.with(Steps::AddCatalog, anything)
        trx.should_receive(:next).once.ordered.with(Steps::EjectCatalogMedia, anything)
        trx.should_receive(:next).once.ordered.with(Steps::DeleteCatalogMedia, anything)
        trx.should_receive(:next).once.ordered.with(Steps::CreateMedia, anything, anything, anything, anything)
        trx.should_receive(:next).once.ordered.with(Steps::UploadMediaFiles, anything)
        trx.should_receive(:next).once.ordered.with(Steps::AddCatalogItem, anything, anything)
        trx.should_receive(:next).once.ordered.with(Steps::InsertCatalogMedia, anything)

        t = trx
        subject.instance_eval{save_agent_env(t)}
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
