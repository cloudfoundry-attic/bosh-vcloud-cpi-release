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
        subject.stub(:steps).and_yield(trx).and_return(trx)
      end

      let(:trx) do
        trx = double("Transaction")
        trx.stub(:state) { state }
        trx
      end

      let(:client) do
        client = double("client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:resolve_entity).with(vm_id).and_return vm
        client.stub(:resolve_link).with(vm_link).and_return vm
        client.stub(:resolve_entity).with(vapp_id).and_return vapp
        client.stub(:resolve_link).with(vapp_link).and_return vapp
        client.stub(:resolve_entity).with(disk_id).and_return disk
        client.stub(:reload) { |obj| obj }
        client.stub(:flush_cache)
        client
      end

      let(:state) { {} }
      let(:vapp_id) { "vapp_id" }
      let(:vapp_link) { "vapp_link" }
      let(:vapp) { vapp = double(vapp_id) }

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

      it "create_stemcell" do
        image = "stemcell_name"
        result = "urn"
        trx.should_receive(:next).once.ordered.with(Steps::StemcellInfo, image)
        trx.should_receive(:next).once.ordered.with(Steps::CreateTemplate, anything)
        trx.should_receive(:next).once.ordered.with(Steps::UploadTemplateFiles)
        trx.should_receive(:next).once.ordered.with(Steps::AddCatalogItem, anything, anything)
        trx.stub_chain("[].urn").and_return(result)

        subject.create_stemcell(image, nil).should == result
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

      it "raise error if vapp is not found" do
        client.stub(:resolve_entity).with(vapp_id).and_return nil

        expect { subject.delete_stemcell(vapp_id)}.to raise_error /not found/
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
          catalog_vapp_id, anything, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::CreateOrUpdateAgentEnv, anything, anything, anything
        )
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOn, anything)
        trx.stub_chain("[].urn").and_return result
        trx.stub_chain("state.[]").with(:vapp).and_return vapp
        trx.stub_chain("state.[]=")
        subject.stub(:reconfigure_vm)
        subject.stub(:save_agent_env)

        subject.create_vm(agent_id, catalog_vapp_id,
                          resource_pool, nil).
                          should == result
      end

      it "should reuse existing vapp" do
        vapp_name = "existing_vapp"
        environment = {"vapp" => vapp_name}
        agent_id = "agent_id"
        catalog_vapp_id = "catalog_vapp_id"
        vm_link = "vm_link"
        resource_pool = double("resource pool")
        networks = double("networks")
        existing_vapp = double("existing_vapp")
        existing_vapp.stub(:name).and_return vapp_name
        existing_vapp.should_receive(:vms).and_return []
        # after recompose
        existing_vapp.should_receive(:vms).and_return [vm]
        vm.stub_chain("hardware_section.hard_disks").and_return []
        vm.stub(:href) { vm_link }
        vapp.stub_chain("vms.[]").and_return vm
        result = "urn"
        trx.should_receive(:next).once.ordered.with(
          Steps::Instantiate,
          catalog_vapp_id,
          anything,
          anything,
          anything )
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
        trx.stub_chain("[].urn").and_return result
        trx.stub_chain("state.[]").with(:vapp).and_return vapp
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

      it "pown on a vm when it's powered off" do
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
    end

    describe ".configure_networks" do
      include_context "base"

      it "config network" do
        vm_name = "vm_name"
        network = {
          'cloud_properties' => { 'name' => "demo_network"}
        }
        networks = { demo_network: network }
        vm.stub(:name) { vm_name }
        vapp.stub(:vms) { [vm, vm2] }
        client.stub_chain("vdc.storage_profiles")
        state[:vm] = vm
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOff, anything, anything )
        trx.should_receive(:next).once.ordered.with(
          Steps::AddNetworks, anything )
        trx.should_receive(:next).once.ordered.with(
          Steps::ReconfigureVM, anything, anything, anything,
          networks )
        trx.should_receive(:next).once.ordered.with(
          Steps::DeleteUnusedNetworks, anything )
        trx.should_receive(:next).once.ordered.with(
          Steps::LoadAgentEnv )
        trx.should_receive(:next).once.ordered.with(
          Steps::SaveAgentEnv )
        trx.should_receive(:next).once.ordered.with(
          Steps::EjectCatalogMedia, vm_name)
        trx.should_receive(:next).once.ordered.with(
          Steps::DeleteCatalogMedia, vm_name)
        trx.should_receive(:next).once.ordered.with(
          Steps::UploadCatalogMedia, vm_name,
          anything, anything, anything )
        trx.should_receive(:next).once.ordered.with(
          Steps::AddCatalogItem, anything, anything)
        trx.should_receive(:next).once.ordered.with(
          Steps::InsertCatalogMedia, vm_name)
        trx.should_receive(:next).once.ordered.with(
          Steps::PowerOn, anything
        )
        Steps::CreateOrUpdateAgentEnv.stub(:update_network_env)

        subject.configure_networks(vm_id, networks)
      end
    end

    describe ".create_disk" do
      include_context "base"

      it "create a disk" do
        size_mb = 10
        result = "disk_urn"
        trx.should_receive(:next).once.ordered.with(
          Steps::CreateDisk, anything, size_mb, nil
        )
        trx.stub_chain("[].urn").and_return result

        subject.create_disk(size_mb).should == result
      end

      it "create disk with vm locality" do
        size_mb = 10
        vm_locality = [ vm ]
        result = "disk_urn"
        client.should_receive(:resolve_entity).with(vm_locality).
          and_return vm
        trx.should_receive(:next).once.ordered.with(
          Steps::CreateDisk, anything, size_mb, vm
        )
        trx.stub_chain("[].urn").and_return result

        subject.create_disk(size_mb, vm_locality).should == result
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

      it "delete a disk" do
        client = double("client")
        trx.should_receive(:next).once.ordered.with(
          Steps::Delete, disk, true)
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client.stub(:resolve_entity).with(disk_id).and_return disk

        subject.delete_disk(disk_id)
      end
    end
  end
end
