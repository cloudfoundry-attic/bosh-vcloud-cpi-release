require 'securerandom'
require 'logger'
require 'common/common'

require_relative 'errors'
require_relative 'vcd_client'
require_relative 'steps'

module VCloudCloud

  class Cloud < ::Bosh::Cloud

    def initialize(options)
      @logger = Bosh::Clouds::Config.logger
      @logger.debug "Input cloud options: #{options.inspect}"

      @agent_properties = options['agent'] || {}

      vcds = options['vcds']
      raise ArgumentError, 'Invalid number of VCDs' unless vcds && vcds.size == 1
      @vcd = vcds[0]

      @entities = @vcd['entities']
      raise ArgumentError, 'Invalid entities in VCD settings' unless @entities && @entities.is_a?(Hash)

      @client = VCloudClient.new(@vcd, @logger)
    end

    def create_stemcell(image, _)
      (steps "create_stemcell(#{image}, _)" do |s|
        s.next Steps::StemcellInfo, image
        catalog_type = :vapp
        s.next Steps::AddCatalog, @client.catalog_name(catalog_type)
        s.next Steps::CreateTemplate, "sc-#{unique_name}", catalog_type

        # Retry upload template file in case of timeout
        errors = [Timeout::Error]
        Bosh::Common.retryable(sleep: cpi_call_wait_time, tries: cpi_retries, on: errors) do |tries, error|
          s.next Steps::UploadTemplateFiles
        end
      end)[:catalog_item].urn
    end

    def delete_stemcell(catalog_vapp_id)
      steps "delete_stemcell(#{catalog_vapp_id})" do |s|
        begin
          catalog_vapp = client.resolve_entity catalog_vapp_id
          if catalog_vapp.nil?
            @logger.warn "Catalog vApp #{catalog_vapp_id} not found, skip the error"
            return
          end

          vapp = client.resolve_link catalog_vapp.entity
          client.wait_entity vapp, true
          client.invoke :delete, vapp.remove_link
          client.invoke :delete, catalog_vapp.href
        rescue RestClient::Forbidden, ObjectNotFoundError => e
          @logger.warn "get #{e.message} error while deleting Catalog vApp #{catalog_vapp_id} in #delete_stemcell, skip the error"
          return
        end
      end
    end

    def cpi_call_wait_time
      2
    end

    def cpi_retries
      10
    end

    def create_vm(agent_id, catalog_vapp_id, resource_pool, networks, disk_locality = nil, environment = nil)
      (steps "create_vm(#{agent_id}, #{catalog_vapp_id}, #{resource_pool}, ...)" do |s|
        # disk_locality should be an array of disk ids
        disk_locality = independent_disks disk_locality

        # agent_id is used as vm name
        description = @entities['description']

        requested_name = environment && environment['vapp']
        vapp_name = requested_name ? "vapp-tmp-#{unique_name}" : agent_id

        storage_profiles = client.vdc.storage_profiles || []
        storage_profile = storage_profiles.find { |sp| sp['name'] == @entities['vapp_storage_profile'] }


        s.next Steps::Instantiate, catalog_vapp_id, vapp_name, description, disk_locality, storage_profile
        client.flush_cache # flush cached vdc which contains vapp list
        vapp = s.state[:vapp]
        vm = s.state[:vm] = vapp.vms[0]

        # save original disk configuration
        s.state[:disks] = Array.new(vm.hardware_section.hard_disks)
        reconfigure_vm s, agent_id, description, resource_pool, networks

        vapp, vm =[s.state[:vapp], s.state[:vm]]

        # To handle concurrent create_vm requests,
        # if the target vApp exists, creates a temp vApp, and then recomposes its VM to the target vApp.
        if requested_name
          container_vapp = nil

          errors = [RuntimeError]
          Bosh::Common.retryable(sleep: cpi_call_wait_time, tries: cpi_retries, on: errors) do |tries, error|
            begin
              begin
                @logger.debug "Requesting container vApp: #{requested_name}"
                container_vapp = client.vapp_by_name requested_name
              rescue ObjectNotFoundError
                # ignored, keep container_vapp nil
                @logger.debug "Invalid container vApp: #{requested_name}"
              end

              if container_vapp
                @logger.debug "Enter recompose, container_vapp: #{container_vapp.name}"
                begin
                  s.next Steps::Recompose, container_vapp.name, container_vapp, vm
                rescue VCloudCloud::ObjectExistsError => e
                  @logger.debug "VM already exists, skip the error"
                end
              else
                # just rename the vApp
                container_vapp = vapp
                s.next Steps::Recompose, requested_name, container_vapp
              end
            rescue Exception => e
              @logger.warn "Caught an exception during create_vm Exception #{e}, Type #{e.class} Message #{e.message}"
              @logger.warn "Exception trace #{e.backtrace.join('\n')}"
              raise "re raising exception #{e.message} in create_vm"
            end
          end

          # delete tmp vapp only if the name is different from requested
          client.flush_cache
          vapp = client.reload vapp
          client.wait_entity vapp, true
          if vapp.name != requested_name
            begin
              s.next Steps::Delete, vapp, true
            rescue Exception => ex
              @logger.warn "Caught exception when trying to delete tmp vapp #{vapp.name}: #{ex.to_s}"
            end
          end

          # Wait for Delete/Recompose step to finish, retry if fails
          # reload all the stuff
          client.flush_cache
          vapp = client.reload container_vapp
          client.wait_entity vapp, true

          vms = vapp.vms.select { |v| v.name == vm.name }

          raise "New virtual machine not found in recomposed vApp" if vms.empty?
          s.state[:vm] = client.resolve_link vms[0].href
        end

        # create env and generate env ISO image
        s.state[:env_metadata_key] = @entities['vm_metadata_key']
        s.next Steps::CreateOrUpdateAgentEnv, networks, environment, @agent_properties

        # TODO refact this
        if requested_name
          errors = [RuntimeError]
          Bosh::Common.retryable(sleep: cpi_call_wait_time, tries: cpi_retries, on: errors) do |tries, error|
            begin
              save_agent_env s
              s.next Steps::PowerOn, :vm
            rescue Exception => e
              @logger.warn "Caught an exception during create_vm Exception #{e}, Type #{e.class} Message #{e.message}"
              @logger.warn "Exception trace #{e.backtrace.join('\n')}"
              raise "re raising exception #{e.message} in create_vm"
            end
          end
        else
          save_agent_env s
          s.next Steps::PowerOn, :vm
        end

        s.state[:vapp] = vapp
        s.state
      end)[:vm].urn
    end

    def reboot_vm(vm_id)
      steps "reboot_vm(#{vm_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity(vm_id)

        errors = [RuntimeError]
        Bosh::Common.retryable(sleep: cpi_call_wait_time, tries: cpi_retries, on: errors) do |tries, error|
          begin
            if vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
              s.next Steps::DiscardSuspendedState, :vm
              s.next Steps::PowerOn, :vm
            elsif vm['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
              s.next Steps::PowerOn, :vm
            else
              begin
                s.next Steps::Reboot, :vm
              rescue => ex
                @logger.warn "Caught exception when trying to Reboot vm #{vm_id}: #{ex.to_s}"
                @logger.debug 'Force a hard-reboot when failed to perform a soft-reboot'
                s.next Steps::PowerOff, :vm, true
                s.next Steps::PowerOn, :vm
              end
            end
          rescue Exception => e
            @logger.warn "Caught an exception during reboot_vm Exception #{e}, Type #{e.class} Message #{e.message}"
            @logger.warn "Exception trace #{e.backtrace.join('\n')}"
            raise "re raising exception #{e.message} in reboot_vm"
          end
        end
      end
    end

    def has_vm?(vm_id)
      vm = client.resolve_entity vm_id
      vm.type == VCloudSdk::Xml::MEDIA_TYPE[:VM]
    rescue RestClient::Exception # invalid ID will get 403
      false
    rescue ObjectNotFoundError
      false
    end

    def delete_vm(vm_id)
      steps "delete_vm(#{vm_id})" do |s|
        begin
          vm = s.state[:vm] = client.resolve_entity vm_id

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

          s.next Steps::DeleteCatalogMedia, vm.name
        rescue RestClient::Forbidden, ObjectNotFoundError => e
          @logger.warn "get #{e.message} error while deleting vm #{vm_id} likely due to non-existence, skip the error"
          return
        end
      end
    end

    def configure_networks(vm_id, networks)
      raise Bosh::Clouds::NotSupported, 'VDC CPI was configured to return NotSupported'
    end

    def create_disk(size_mb, cloud_properties, vm_locality = nil)
      (steps "create_disk(#{size_mb}, #{cloud_properties.inspect}, #{vm_locality.inspect})" do |s|
        # vm_locality is used as vm_id
        vm = vm_locality.nil? ? nil : client.resolve_entity(vm_locality)
        storage_profiles = client.vdc.storage_profiles || []
        storage_profile = storage_profiles.find { |sp| sp['name'] == @entities['vapp_storage_profile'] }
        s.next Steps::CreateDisk, unique_name, size_mb, vm, storage_profile
      end)[:disk].urn
    end

    def attach_disk(vm_id, disk_id)
      steps "attach_disk(#{vm_id}, #{disk_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id

        # vm.hardware_section will change, save current state of disks
        previous_disks_list = Array.new(vm.hardware_section.hard_disks)

        s.state[:disk] = client.resolve_entity disk_id

        errors = [RuntimeError]
        Bosh::Common.retryable(sleep: cpi_call_wait_time, tries: cpi_retries, on: errors) do |tries, error|
          begin
            s.next Steps::AttachDetachDisk, :attach

            # update environment
            s.state[:env_metadata_key] = @entities['vm_metadata_key']
            s.next Steps::LoadAgentEnv

            vm = s.state[:vm] = client.reload vm
            Steps::CreateOrUpdateAgentEnv.update_persistent_disk s.state[:env], vm, disk_id, previous_disks_list

            save_agent_env s
          rescue Exception => e
            @logger.warn "Caught an exception during attach_disk Exception #{e}, Type #{e.class} Message #{e.message}"
            @logger.warn "Exception trace #{e.backtrace.join('\n')}"
            raise "re raising exception #{e.message} in attach_disk"
          end
        end
      end
    end

    def detach_disk(vm_id, disk_id)
      steps "detach_disk(#{vm_id}, #{disk_id})" do |s|
        vm = s.state[:vm] = client.resolve_entity vm_id
        s.state[:disk] = client.resolve_entity disk_id
        # if disk is not attached, just ignore
        next unless vm.find_attached_disk s.state[:disk]

        errors = [RuntimeError]
        Bosh::Common.retryable(sleep: cpi_call_wait_time, tries: cpi_retries, on: errors) do |tries, error|
          begin
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
          rescue Exception => e
            @logger.warn "Caught an exception during detach_disk Exception #{e}, Type #{e.class} Message #{e.message}"
            @logger.warn "Exception trace #{e.backtrace.join('\n')}"
            raise "re raising exception #{e.message} in detach_disk"
          end
        end
      end
    end

    def delete_disk(disk_id)
      steps "delete_disk(#{disk_id})" do |s|
        begin
          disk = client.resolve_entity disk_id
          s.next Steps::Delete, disk, true
        rescue RestClient::Forbidden, ObjectNotFoundError => e
          @logger.warn "got #{e.message} error while deleting disk #{disk_id}, skip the error"
          return
        end
      end
    end

    def get_disk_size_mb(disk_id)
      client.resolve_entity(disk_id).size_mb
    end

    def validate_deployment(old_manifest, new_manifest)
    end

    def client
      @client
    end

    private

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
      networks.map { |k, v| v['cloud_properties']['name'] }.uniq
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

      s.next Steps::AddCatalog, @client.catalog_name(:media)

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
