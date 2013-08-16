require 'securerandom'
require 'logger'

require_relative 'errors'
require_relative 'vcd_client'
require_relative 'steps'

module VCloudCloud

  class Cloud

    def initialize(options)
      @logger = Bosh::Clouds::Config.logger
      @logger.debug "Input cloud options: #{options.inspect}"

      @agent_properties = options['agent'] || {}

      vcds = options['vcds']
      raise ArgumentError, 'Invalid number of VCDs' unless vcds && vcds.size == 1
      @vcd = vcds[0]

      @entities = @vcd['entities']
      raise ArgumentError, 'Invalid entities in VCD settings' unless @entities && @entities.is_a?(Hash)

      @client_lock = Mutex.new # lock for establishing client connection
      @vapp_lock   = Mutex.new # lock for recompose vApp and delete vm from vApp
    end

    def create_stemcell(image, _)
      (steps "create_stemcell(#{image}, _)" do |s|
        s.next Steps::StemcellInfo, image
        s.next Steps::CreateTemplate, "sc-#{unique_name}"
        s.next Steps::UploadTemplateFiles
        s.next Steps::AddCatalogItem, :vapp, s.state[:vapp_template]
      end)[:catalog_item].urn
    end

    def delete_stemcell(catalog_vapp_id)
      steps "delete_stemcell(#{catalog_vapp_id})" do |s|
        catalog_vapp = client.resolve_entity catalog_vapp_id
        raise "Catalog vApp #{catalog_vapp_id} not found" unless catalog_vapp
        vapp = client.resolve_link catalog_vapp.entity
        client.wait_entity vapp, true
        client.invoke :delete, vapp.remove_link
        client.invoke :delete, catalog_vapp.href
      end
    end

    def create_vm(agent_id, catalog_vapp_id, resource_pool, networks, disk_locality = nil, environment = nil)
      (steps "create_vm(#{agent_id}, #{catalog_vapp_id}, #{resource_pool}, ...)" do |s|
        # disk_locality should be an array of disk ids
        disk_locality = independent_disks disk_locality

        # agent_id is used as vm name
        description = @entities['description']

        requested_name = environment && environment['vapp']
        vapp_name = requested_name ? "vapp-tmp-#{unique_name}" : agent_id

        s.next Steps::Instantiate, catalog_vapp_id, vapp_name, description, disk_locality
        client.flush_cache  # flush cached vdc which contains vapp list
        vapp = s.state[:vapp]
        vm = s.state[:vm] = vapp.vms[0]

        # save original disk configuration
        s.state[:disks] = Array.new(vm.hardware_section.hard_disks)
        reconfigure_vm s, agent_id, description, resource_pool, networks

        vapp, vm =[s.state[:vapp], s.state[:vm]]

        # recompose if requested
        if requested_name
          container_vapp = nil
          vm_href = nil
          existing_vm_hrefs = []

          @vapp_lock.synchronize do
            begin
              @logger.debug "Requesting container vApp: #{requested_name}"
              container_vapp = client.vapp_by_name requested_name
            rescue ObjectNotFoundError
              # ignored, keep container_vapp nil
              @logger.debug "Invalid container vApp: #{requested_name}"
            end

            if container_vapp
              existing_vm_hrefs = container_vapp.vms.map { |v| v.href }
              s.next Steps::Recompose, container_vapp.name, container_vapp, vm
              client.flush_cache
              vapp = s.state[:vapp] = client.reload vapp
              client.wait_entity vapp
              s.next Steps::Delete, vapp, true
            else
              # just rename the vApp
              container_vapp = vapp
              s.next Steps::Recompose, requested_name, container_vapp
            end

            # reload all the stuff
            client.flush_cache
            vapp = s.state[:vapp] = client.reload container_vapp
            client.wait_entity vapp
            vm_href = vapp.vms.map { |v| v.href } - existing_vm_hrefs
          end

          raise "New virtual machine not found in recomposed vApp" if vm_href.empty?
          s.state[:vm] = client.resolve_link vm_href[0]
        end

        # create env and generate env ISO image
        s.state[:env_metadata_key] = @entities['vm_metadata_key']
        s.next Steps::CreateOrUpdateAgentEnv, networks, environment, @agent_properties

        # TODO refact this
        if requested_name
          @vapp_lock.synchronize do
            save_agent_env s
            s.next Steps::PowerOn, :vm
          end
        else
          save_agent_env s
          s.next Steps::PowerOn, :vm
        end
      end)[:vm].urn
    end

    def reboot_vm(vm_id)
      steps "reboot_vm(#{vm_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity(vm_id)

        @vapp_lock.synchronize do
          if vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
            s.next Steps::DiscardSuspendedState, :vm
            s.next Steps::PowerOn, :vm
          elsif vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
            s.next Steps::PowerOn, :vm
          else
            s.next Steps::Reboot, :vm
          end
        end
      end
    end

    def has_vm?(vm_id)
      vm = client.resolve_entity vm_id
      vm.type == VCloudSdk::Xml::MEDIA_TYPE[:VM]
    rescue RestClient::Exception  # invalid ID will get 403
      false
    rescue ObjectNotFoundError
      false
    end

    def delete_vm(vm_id)
      steps "delete_vm(#{vm_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id

        @vapp_lock.synchronize do
          # poweroff vm before we are able to delete it
          s.next Steps::PowerOff, :vm, true

          vapp = s.state[:vapp] = client.resolve_link vm.container_vapp_link
          if vapp.vms.size == 1
            # Hack: if vApp is running, and the last VM is deleted, it is no longer stoppable and removable
            # even from dashboard. So if there's only one VM, just stop and delete the vApp
            s.next Steps::PowerOff, :vapp, true
            s.next Steps::Undeploy, :vapp
            s.next Steps::Delete, s.state[:vapp], true
          else
            s.next Steps::Undeploy, :vm
            s.next Steps::Delete, s.state[:vm], true
          end
        end

        s.next Steps::DeleteCatalogMedia, vm.name
      end
    end

    def configure_networks(vm_id, networks)
      steps "configure_networks(#{vm_id}, #{networks})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id

        @vapp_lock.synchronize do
          # power off vm first
          s.next Steps::PowerOff, :vm, true

          # load container vApp
          s.state[:vapp] = client.resolve_link vm.container_vapp_link

          reconfigure_vm s, nil, nil, nil, networks

          # update environment
          s.state[:env_metadata_key] = @entities['vm_metadata_key']
          s.next Steps::LoadAgentEnv
          vm = s.state[:vm] = client.reload vm
          Steps::CreateOrUpdateAgentEnv.update_network_env s.state[:env], vm, networks

          save_agent_env s

          # power on
          s.next Steps::PowerOn, :vm
        end
      end
    end

    def create_disk(size_mb, vm_locality = nil)
      (steps "create_disk(#{size_mb}, #{vm_locality.inspect})" do |s|
        # vm_locality is used as vm_id
        vm = vm_locality.nil? ? nil : client.resolve_entity(vm_locality)
        s.next Steps::CreateDisk, unique_name, size_mb, vm
      end)[:disk].urn
    end

    def attach_disk(vm_id, disk_id)
      steps "attach_disk(#{vm_id}, #{disk_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id

        # vm.hardware_section will change, save current state of disks
        previous_disks_list = Array.new(vm.hardware_section.hard_disks)

        s.state[:disk]  = client.resolve_entity disk_id

        @vapp_lock.synchronize do
          s.next Steps::AttachDetachDisk, :attach

          # update environment
          s.state[:env_metadata_key] = @entities['vm_metadata_key']
          s.next Steps::LoadAgentEnv

          vm = s.state[:vm] = client.reload vm
          Steps::CreateOrUpdateAgentEnv.update_persistent_disk s.state[:env], vm, disk_id , previous_disks_list

          save_agent_env s
        end
      end
    end

    def detach_disk(vm_id, disk_id)
      steps "detach_disk(#{vm_id}, #{disk_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id
        s.state[:disk] = client.resolve_entity disk_id
        # if disk is not attached, just ignore
        next unless vm.find_attached_disk s.state[:disk]

        @vapp_lock.synchronize do
          if vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
            s.next Steps::DiscardSuspendedState, :vm
          end
          s.next Steps::AttachDetachDisk, :detach

          # update environment
          s.state[:env_metadata_key] = @entities['vm_metadata_key']
          s.next Steps::LoadAgentEnv
          env = s.state[:env]
          if env['disks'] && env['disks']['persistent'].is_a?(Hash)
            env['disks']['persistent'].delete disk_id
          end

          save_agent_env s
        end
      end
    end

    def delete_disk(disk_id)
      steps "delete_disk(#{disk_id})" do |s|
        disk = client.resolve_entity disk_id
        s.next Steps::Delete, disk, true
      end
    end

    def get_disk_size_mb(disk_id)
      client.resolve_entity(disk_id).size_mb
    end

    def validate_deployment(old_manifest, new_manifest)
    end

    private

    def client
      @client_lock.synchronize do
        @client = VCloudClient.new(@vcd, @logger) if @client.nil?
      end
      @client
    end

    def steps(name, options = {}, &block)
      Transaction.perform name, client(), options, &block
    end

    def unique_name
      SecureRandom.uuid.to_s
    end

    def independent_disks(disk_locality)
      disk_locality ||= []
      @logger.info "Instantiate vApp accessible to disks: #{disk_locality.join(',')}"
      disk_locality.map do |disk_id|
        client.resolve_entity disk_id
      end
    end

    def network_names(networks)
      networks.map { |k,v| v['cloud_properties']['name'] }.uniq
    end

    def reconfigure_vm(s, name, description, resource_pool, networks)
      net_names = network_names networks
      s.next Steps::AddNetworks, net_names
      s.next Steps::ReconfigureVM, name, description, resource_pool, networks
      s.next Steps::DeleteUnusedNetworks, net_names
    end

    def save_agent_env(s)
      s.next Steps::SaveAgentEnv

      vm = s.state[:vm]

      # eject and delete old env ISO
      s.next Steps::EjectCatalogMedia, vm.name
      s.next Steps::DeleteCatalogMedia, vm.name

      # attach new env ISO
      storage_profiles = client.vdc.storage_profiles || []
      media_storage_profile = storage_profiles.find { |sp| sp['name'] == @entities['media_storage_profile'] }
      s.next Steps::CreateMedia, vm.name, s.state[:iso], 'iso', media_storage_profile
      s.next Steps::UploadMediaFiles, s.state[:iso]
      s.next Steps::AddCatalogItem, :media, s.state[:media]
      s.next Steps::InsertCatalogMedia, vm.name

      s.state[:vm] = client.reload vm
    end
  end
end
