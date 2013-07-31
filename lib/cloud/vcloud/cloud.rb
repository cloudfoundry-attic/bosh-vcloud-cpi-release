require 'securerandom'

require_relative 'errors'
require_relative 'const'
require_relative 'vcd_client'
require_relative 'steps'

module VCloudCloud

  class Cloud

    def initialize(options)
      @logger = Bosh::Clouds::Config.logger
      @logger.debug "Input cloud options: #{options.inspect}"

      @agent_properties = options['agent'] || {}
      
      vcds = options['vcds']
      raise ArgumentError, 'Invalid number of VCDs' unless vcds.size == 1
      @vcd = vcds[0]

      @entities = @vcd['entities']
      @debug = @vcd['debug'] || {}

      @client_lock = Mutex.new
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
        raise "Catalog vApp #{id} not found" unless catalog_vapp
        vapp = client.resolve_link catalog_vapp.entity
        client.wait_entity vapp, true
        client.invoke :delete, vapp.remove_link
        client.invoke :delete, catalog_vapp.href
      end
    end

    def create_vm(agent_id, catalog_vapp_id, resource_pool, networks, disk_locality = nil, environment = nil)
      (steps "create_vm(#{agent_id}, #{catalog_vapp_id}, #{resource_pool}, ...)" do |s|
        # request name available for recomposing vApps
        requested_name = environment && environment['vapp']
        vapp_name = requested_name.nil? ? agent_id : "vapp-tmp-#{unique_name}"

        # disk_locality should be an array of disk ids
        disk_locality = independent_disks disk_locality
        
        # agent_id is used as vm name
        description = @entities['description']
        
        # if requested_name is present, we need to recompose vApp
        container_vapp = nil
        unless requested_name.nil?
          begin
            container_vapp = client.vapp_by_name requested_name
          rescue ObjectNotFoundError
            # ignored, keep container_vapp nil
            vapp_name = agent_id
          end
        end

        s.next Steps::Instantiate, catalog_vapp_id, vapp_name, description, disk_locality
        vapp = s.state[:vapp]
        vm = s.state[:vm] = vapp.vms[0]
        
        # perform recomposing
        if container_vapp
          container_vapp = client.wait_entity container_vapp
          s.next Steps::Recompose, container_vapp
          vapp = s.state[:vapp] = client.reload vapp
          client.wait_entity vapp
          s.next Steps::Delete, vapp, true
          vapp = s.state[:vapp] = container_vapp
        end
        
        # save original disk configuration
        vapp = s.state[:vapp] = client.reload vapp
        vm = s.state[:vm] = client.reload vm
        s.state[:disks] = Array.new(vm.hardware_section.hard_disks)
        
        reconfigure_vm s, agent_id, description, resource_pool, networks
        
        # create env and generate env ISO image
        s.state[:env_metadata_key] = @entities['vm_metadata_key'] 
        s.next Steps::CreateAgentEnv, networks, environment, @agent_properties

        save_agent_env s

        # power on
        s.next Steps::PowerOn, :vm
      end)[:vm].urn
    end
    
    def reboot_vm(vm_id)
      steps "reboot_vm(#{vm_id})" do |s|
        vm = s.state[:vm] = client.resolve_link client.resolve_entity(vm_id)
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

    def has_vm?(vm_id)
      client.resolve_entity vm_id
      true
    rescue RestClient::Exception  # invalid ID will get 403
      false
    rescue ObjectNotFoundError
      false
    end

    def delete_vm(vm_id)
      steps "delete_vm(#{vm_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id
        
        # power off vm first
        if vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          s.next Steps::DiscardSuspendedState, :vm
        end
        s.next Steps::PowerOff, :vm

        vapp_link = vm.container_vapp_link
        
        if @debug['delete_vm']
          s.next Steps::Undeploy, s.state[:vm]
          s.next Steps::Delete, s.state[:vm], true
        end
        
        if @debug['delete_empty_vapp']
          vapp = s.state[:vapp] = client.resolve_link vapp_link
          if vapp.vms.size == 0
            if vapp['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
              s.next Steps::DiscardSuspendedState, :vapp
            end
            vapp = s.state[:vapp]
            if vapp['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_ON].to_s
              s.next Steps::PowerOff, :vapp
            end
            s.next Steps::Delete, s.state[:vapp], true
          end
        end
      end
    end

    def configure_networks(vm_id, networks)
      steps "configure_networks(#{vm_id}, #{networks})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id

        # power off vm first
        if vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
          s.next Steps::DiscardSuspendedState, :vm
        end
        s.next Steps::PowerOff, :vm

        # load container vApp
        vapp = s.state[:vapp] = client.resolve_link vm.container_vapp_link
        
        reconfigure_vm s, nil, nil, nil, networks
        
        # update environment
        s.state[:env_metadata_key] = @entities['vm_metadata_key']
        s.next Steps::LoadAgentEnv
        vm = s.state[:vm] = client.reload vm
        Steps::CreateAgentEnv.update_network_env s.state[:env], vm, networks
        
        save_agent_env s
        
        # power on
        s.next Steps::PowerOn, :vm
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
        s.state[:vm] = client.resolve_entity vm_id
        s.state[:disk] = client.resolve_entity disk_id
        s.next Steps::AttachDetachDisk, :attach
        
        # update environment
        s.state[:env_metadata_key] = @entities['vm_metadata_key']
        s.next Steps::LoadAgentEnv
        s.state[:env]['disks'] ||= {}
        s.state[:env]['disks']['persistent'] ||= {}
        s.state[:env]['disks']['persistent'][disk_id] = disk_id
        
        save_agent_env s
      end
    end

    def detach_disk(vm_id, disk_id)
      steps "detach_disk(#{vm_id}, #{disk_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id
        s.state[:disk] = client.resolve_entity disk_id
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

    def delete_disk(disk_id)
      steps "delete_disk(#{disk_id})" do |s|
        disk = client.resolve_entity disk_id
        s.next Steps::Delete, disk
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
      s.next Steps::UploadCatalogMedia, vm.name, s.state[:iso], 'iso', media_storage_profile
      s.next Steps::AddCatalogItem, :media, s.state[:media]
      s.next Steps::InsertCatalogMedia, vm.name
      
      s.state[:vm] = client.reload vm
    end
  end

end
