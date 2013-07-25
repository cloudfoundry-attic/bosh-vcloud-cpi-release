require "common/common"

require "digest/sha1"
require "fileutils"
require "logger"
require "securerandom"
require "yajl"
require "thread"

require_relative "const"
require_relative "util"

module VCloudCloud

  class Cloud

    def initialize(options)
      @logger = Bosh::Clouds::Config.logger
      VCloudSdk::Config.configure({ "logger" => @logger })
      @logger.debug("Input cloud options: #{options.inspect}")

      @agent_properties = options["agent"]
      vcds = options["vcds"]
      raise ArgumentError, "Invalid number of VCDs" unless vcds.size == 1
      @vcd = vcds[0]

      finalize_options
      @control = @vcd["control"]
      @retries = @control["retries"]
      @logger.info("VCD cloud options: #{options.inspect}")

      @client_lock = Mutex.new

      @vapp_lock = Mutex.new

      at_exit { destroy_client }
    end

    def client
      @client_lock.synchronize {
        if @client.nil?
          create_client
        else
          begin
            @client.get_ovdc
            @client
          rescue VCloudSdk::CloudError => e
            log_exception("validate, creating new session.", e)
            create_client
          end
        end
      }
    end

    def has_vm?(vm_cid)
      @client = client
      @client.get_vm(vm_cid)
      true
    rescue Bosh::Clouds::VMNotFound
      false
    end

    def create_stemcell(image, _)
      @client = client

      with_thread_name("create_stemcell(#{image}, _)") do
        @logger.debug("create_stemcell #{image} #{_}")
        result = nil
        Dir.mktmpdir do |temp_dir|
          @logger.info("Extracting stemcell to: #{temp_dir}")
          output = `tar -C #{temp_dir} -xzf #{image} 2>&1`
          raise "Corrupt image, tar exit status: #{$?.exitstatus} output:" +
            "#{output}" if $?.exitstatus != 0

          ovf_file = Dir.entries(temp_dir).find {
            |entry| File.extname(entry) == ".ovf" }
          raise "Missing OVF" unless ovf_file
          ovf_file = File.join(temp_dir, ovf_file)

          name = "sc-#{generate_unique_name}"
          @logger.info("Generated name: #{name}")

          @logger.info("Uploading #{ovf_file}")
          result = @client.upload_vapp_template(name, temp_dir).urn
        end

        @logger.info("Stemcell created as catalog vApp with ID #{result}.")
        result
      end
    end

    def delete_stemcell(catalog_vapp_id)
      @client = client

      with_thread_name("delete_stemcell(#{catalog_vapp_id})") do
        @logger.debug("delete_stemcell #{catalog_vapp_id}")

        # shadow VMs (stemcell replicas) get deleted serially,
        # and upon failure to delete they must be deleted manually
        # from VCD "stranded items"
        @client.delete_catalog_vapp(catalog_vapp_id)
      end
    end

    def reconfigure_vm_only(vm, vapp, agent_id, resource_pool, networks, environment)
      ram_mb = Integer(resource_pool["ram"])
      cpu = Integer(resource_pool["cpu"])
      disk_mb = Integer(resource_pool["disk"])

      disks = vm.hardware_section.hard_disks
      @logger.debug("disks = #{disks.inspect}")
      raise IndexError, "Invalid number of VM hard disks" unless disks.size == 1
      system_disk = disks[0]
      disks_previous = Array.new(disks)

      add_vapp_networks(vapp, networks)

      @logger.info("Reconfiguring VM hardware: #{ram_mb} MB RAM, #{cpu} CPU, " +
                   "#{disk_mb} MB disk, #{networks}.")
      @client.reconfigure_vm(vm) do |v|
        v.name = agent_id
        v.description = @vcd["entities"]["description"]
        v.change_cpu_count(cpu)
        v.change_memory(ram_mb)
        v.add_hard_disk(disk_mb)
        v.delete_nic(*vm.hardware_section.nics)
        add_vm_nics(v, networks)
      end

      delete_vapp_networks(vapp, networks)

      # refresh after reconfiguring
      vm = @client.reload_vm(vm)

      ephemeral_disk = get_newly_added_disk(vm, disks_previous)

      # prepare guest customization settings
      network_env = generate_network_env(vm.hardware_section.nics, networks)
      disk_env = generate_disk_env(system_disk, ephemeral_disk)
      env = generate_agent_env(agent_id, vm, agent_id, network_env, disk_env)
      env["env"] = environment
      @logger.info("Setting VM env: #{vm.urn} #{env.inspect}")
      set_agent_env(vm, env)
    rescue VCloudSdk::CloudError
      delete_vm(vm.urn)
      raise
    end

    def create_vm(agent_id, catalog_vapp_id, resource_pool, networks,
        disk_locality = nil, environment = {})
      @client = client

      with_thread_name("create_vm(#{agent_id}, ...)") do
        Util.retry_operation("create_vm(#{agent_id}, ...)", @retries["cpi"],
            @control["backoff"]) do

          requested_vapp_name = environment["vapp"]

          @logger.info("Creating VM: #{agent_id} in catalog: #{catalog_vapp_id} - VAPP: #{requested_vapp_name || "NOT SPECIFIED"}")
          @logger.debug("networks: #{networks.inspect}")

          locality = independent_disks(disk_locality)

          # Use agent_id as vapp_name unless a specific vapp_name was specified
          temporary_vapp_name = requested_vapp_name.nil? ? agent_id  : "vapp-tmp-#{generate_unique_name}"
          recompose_required = !requested_vapp_name.nil?

          vapp_temporary = @client.instantiate_vapp_template(catalog_vapp_id, # stemcell cid
            temporary_vapp_name, @vcd["entities"]["description"], locality)

          @logger.debug("Instantiated vApp: name=#{vapp_temporary.name}, agent_id: #{agent_id} using stemcell(vapp) id: #{catalog_vapp_id}")
          vm_temporary = vapp_temporary.vms[0]

          newly_instantiated_vm = vm_temporary
          container_vapp = vapp_temporary

          if recompose_required
            # Re-compose vapp - if we instantiated a new temporary vapp then we need to move the new vm into the
            # existing "requested_vapp_name"ed vapp

            # Check if the vapp exists already from a previous create_vm
            @vapp_lock.synchronize {
              begin
                container_vapp = @client.get_vapp_by_name(requested_vapp_name)
                @logger.debug("Found: #{requested_vapp_name}")
              rescue => e
                container_vapp = nil
                @logger.debug("Vapp: #{requested_vapp_name} not found (#{e}). Renaming #{temporary_vapp_name} to #{requested_vapp_name}")
              end

              if container_vapp.nil?
                Util.retry_operation("rename_vapp(#{vapp_temporary.name} -> #{requested_vapp_name})",
                                     @retries["default"],
                                     @control["backoff"]) do
                  @client.recompose_vapp(vapp_temporary, requested_vapp_name, nil, nil)
                end
                @logger.debug("Rename successful")
                container_vapp = vapp_temporary
              else
                @logger.debug("Adding vapp: #{vapp_temporary.name} to #{requested_vapp_name}")
                Util.retry_operation("move vms from (#{vapp_temporary.name} -> #{requested_vapp_name})",
                                     @retries["default"],
                                     @control["backoff"]) do

                  @client.recompose_vapp(container_vapp, requested_vapp_name, [vapp_temporary.href], nil)
                end

                # After recompose, the href/id of the recomposed vm changes, so update the information for the
                # vm_temporary

                container_vapp = @client.get_vapp_by_name(requested_vapp_name) # update
                newly_instantiated_vm = container_vapp.vm(vm_temporary.name)
                @logger.debug("Recomposed #{vm_temporary.name}")

                @logger.debug("Delete source temporary vapp: #{vapp_temporary.name}")
                Util.retry_operation("delete (#{vapp_temporary.name})",
                                     @retries["default"],
                                     @control["backoff"]) do
                  @client.delete_vapp(vapp_temporary)
                end

                @logger.debug("Deleted temporary vapp: #{vapp_temporary.name}")
              end

              reconfigure_vm_only(newly_instantiated_vm, container_vapp, agent_id, resource_pool, networks, environment)
              @logger.info("Created VM: #{newly_instantiated_vm.urn} for agent id: #{agent_id}")

              Util.retry_operation("Power on vm: #{newly_instantiated_vm.urn}",
                                   @retries["default"],
                                   @control["backoff"]) do

                @client.power_on_vm(newly_instantiated_vm)
              end
            }
          else
              reconfigure_vm_only(newly_instantiated_vm, container_vapp, agent_id, resource_pool, networks, environment)
              @logger.info("Created VM: #{newly_instantiated_vm.urn} for agent id: #{agent_id}")

              Util.retry_operation("Power on vm: #{newly_instantiated_vm.urn}",
                                   @retries["default"],
                                   @control["backoff"]) do

                @client.power_on_vm(newly_instantiated_vm)
              end
          end


          newly_instantiated_vm.urn
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("create vApp", e)
      raise e
    end

    def delete_vm(vm_id)
      @client = client

      with_thread_name("delete_vm(#{vm_id}, ...)") do
        Util.retry_operation("delete_vm(#{vm_id}, ...)", @retries["cpi"],
            @control["backoff"]) do
          @logger.info("Deleting vm: #{vm_id}")
          vm = @client.get_vm(vm_id)
          vm_name = vm.name

          # Store the container vapp
          container_vapp_link = vm.container_vapp_link

          begin
            @client.power_off_vm(vm)
          rescue VCloudSdk::VmSuspendedError => e
            @client.discard_suspended_state_vm(vm)
            @client.power_off_vm(vm)
          end
          del_vm = @vcd["debug"]["delete_vm"]
          @client.delete_vm(vm) if del_vm
          @logger.info("#{del_vm ? "Deleted" : "Powered off"} vm: #{vm_id}")


          # Delete vapp if this is the last vm in the vapp
          # TODO: Enable this by setting DELETE_EMPTY_VAPP = true in const.rb
          # Disabled because vapp doesn't expose the required links although the operations are valid
          # Needs more investigation
          delete_empty_vapp = @vcd["debug"]["delete_empty_vapp"]
          if delete_empty_vapp
            @vapp_lock.synchronize {
              container_vapp = nil
              begin
                container_vapp = @client.reload_vapp(container_vapp_link)
              rescue => e
                # if the vapp was already deleted, then we return gracefully rather than throwing error
                @logger.info("Failed to reload container vapp due to: #{e}")
              end

              if ! container_vapp.nil?
                @logger.info("Container vApp: #{container_vapp.name} contains #{container_vapp.vms.size} VMs")
                if container_vapp.vms.size == 0
                  begin
                    @client.power_off_vapp(container_vapp)
                  rescue VCloudSdk::VappSuspendedError => e
                    @client.discard_suspended_state_vapp(container_vapp)
                    @client.power_off_vapp(container_vapp)
                  end

                  @client.delete_vapp(container_vapp)
                end
              else
                # Container vapp was probably already deleted
                @logger.info("Container vapp details could not be loaded, skipping...")
              end
            }
          else
            @logger.info("Skipping checking for empty vapp")
          end
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("delete vm #{vm_id}", e)
      raise e
    end

    def reboot_vm(vm_id)
      @client = client

      with_thread_name("reboot_vm(#{vm_id}, ...)") do
        Util.retry_operation("reboot_vm(#{vm_id}, ...)", @retries["cpi"],
            @control["backoff"]) do
          @logger.info("Rebooting vm: #{vm_id}")
          vm = @client.get_vm(vm_id)
          begin
            @client.reboot_vm(vm)
          rescue VCloudSdk::VmPoweredOffError => e
            @client.power_on_vm(vm)
          rescue VCloudSdk::VmSuspendedError => e
            @client.discard_suspended_state_vm(vm)
            @client.power_on_vm(vm)
          end
          @logger.info("Rebooted vm: #{vm_id}")
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("reboot vm #{vm_id}", e)
      raise e
    end

    def configure_networks(vapp_id, networks)
      @client = client

      with_thread_name("configure_networks(#{vapp_id}, ...)") do
        Util.retry_operation("configure_networks(#{vapp_id}, ...)",
            @retries["cpi"], @control["backoff"]) do
          @logger.info("Reconfiguring vApp networks: #{vapp_id}")
          vapp, vm = get_vapp_vm_by_vapp_id(vapp_id)
          @logger.debug("Powering off #{vapp.name}.")
          begin
            @client.power_off_vapp(vapp)
          rescue VCloudSdk::VappSuspendedError => e
            @client.discard_suspended_state_vapp(vapp)
            @client.power_off_vapp(vapp)
          end

          add_vapp_networks(vapp, networks)
          @client.reconfigure_vm(vm) do |v|
            v.delete_nic(*vm.hardware_section.nics)
            add_vm_nics(v, networks)
          end
          delete_vapp_networks(vapp, networks)

          vapp, vm = get_vapp_vm_by_vapp_id(vapp_id)
          env = get_current_agent_env(vm)
          env["networks"] = generate_network_env(vm.hardware_section.nics,
            networks)
          @logger.debug("Updating agent env to: #{env.inspect}")
          set_agent_env(vm, env)

          @logger.debug("Powering #{vapp.name} back on.")
          @client.power_on_vapp(vapp)
          @logger.info("Configured vApp networks: #{vapp}")
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("configure vApp networks: #{vapp}", e)
      raise e
    end

    def attach_disk(vm_id, disk_id)
      @client = client

      with_thread_name("attach_disk(#{vm_id} #{disk_id})") do
        Util.retry_operation("attach_disk(#{vm_id}, #{disk_id})",
            @retries["cpi"], @control["backoff"]) do
          @logger.info("Attaching disk: #{disk_id} on vm: #{vm_id}")

          vm = @client.get_vm(vm_id)
          # vm.hardware_section will change, save current state of disks
          disks_previous = Array.new(vm.hardware_section.hard_disks)

          disk = @client.get_disk(disk_id)
          @client.attach_disk(disk, vm)

          vm = @client.get_vm(vm_id)
          persistent_disk = get_newly_added_disk(vm, disks_previous)

          env = get_current_agent_env(vm)
          env["disks"]["persistent"][disk_id] = persistent_disk.disk_id
          @logger.info("Updating agent env to: #{env.inspect}")
          set_agent_env(vm, env)

          @logger.info("Attached disk:#{disk_id} to VM:#{vm_id}")
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("attach disk", e)
      raise e
    end

    def detach_disk(vm_id, disk_id)
      @client = client

      with_thread_name("detach_disk(#{vm_id} #{disk_id})") do
        Util.retry_operation("detach_disk(#{vm_id}, #{disk_id})",
            @retries["cpi"], @control["backoff"]) do
          @logger.info("Detaching disk: #{disk_id} from vm: #{vm_id}")

          vm = @client.get_vm(vm_id)

          disk = @client.get_disk(disk_id)
          begin
            @client.detach_disk(disk, vm)
          rescue VCloudSdk::VmSuspendedError => e
            @client.discard_suspended_state_vm(vm)
            @client.detach_disk(disk, vm)
          end

          env = get_current_agent_env(vm)
          env["disks"]["persistent"].delete(disk_id)
          @logger.info("Updating agent env to: #{env.inspect}")
          set_agent_env(vm, env)

          @logger.info("Detached disk: #{disk_id} on vm: #{vm_id}")
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("detach disk", e)
      raise e
    end

    def create_disk(size_mb, vm_locality = nil)
      @client = client

      with_thread_name("create_disk(#{size_mb}, vm_locality)") do
        Util.retry_operation("create_disk(#{size_mb}, vm_locality)",
            @retries["cpi"], @control["backoff"]) do
          @logger.info("Create disk: #{size_mb}, #{vm_locality}")
          disk_name = "#{generate_unique_name}"
          disk = nil
          if vm_locality.nil?
            @logger.info("Creating disk: #{disk_name} #{size_mb}")
            disk = @client.create_disk(disk_name, size_mb)
          else
            # vm_locality => vapp_id
            vm = @client.get_vm(vm_locality)
            @logger.info("Creating disk: #{disk_name} #{size_mb} #{vm.name}")
            disk = @client.create_disk(disk_name, size_mb, vm)
          end
          @logger.info("Created disk: #{disk_name} #{disk.urn} #{size_mb} " +
            "#{vm_locality}")
          disk.urn
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("create disk", e)
      raise e
    end

    def delete_disk(disk_id)
      @client = client

      with_thread_name("delete_disk(#{disk_id})") do
        Util.retry_operation("delete_disk(#{disk_id})", @retries["cpi"],
            @control["backoff"]) do
          @logger.info("Deleting disk: #{disk_id}")
          disk = @client.get_disk(disk_id)
          @client.delete_disk(disk)
          @logger.info("Deleted disk: #{disk_id}")
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("delete disk", e)
      raise e
    end

    def get_disk_size_mb(disk_id)
      @client = client

      with_thread_name("get_disk_size(#{disk_id})") do
        Util.retry_operation("get_disk_size(#{disk_id})", @retries["cpi"],
            @control["backoff"]) do
          @logger.info("Getting disk size: #{disk_id}")
          disk = @client.get_disk(disk_id)
          @logger.info("Disk #{disk_id} size: #{disk.size_mb} MB")
          disk.size_mb
        end
      end
    rescue VCloudSdk::CloudError => e
      log_exception("get_disk_size", e)
      raise e
    end

    def validate_deployment(old_manifest, new_manifest)
      # There is TODO in vSphere CPI that questions the necessity of this method
      raise NotImplementedError, "validate_deployment"
    end

    private

    def finalize_options
      @vcd["control"] = {} unless @vcd["control"]
      @vcd["control"]["retries"] = {} unless @vcd["control"]["retries"]
      @vcd["control"]["retries"]["default"] ||= RETRIES_DEFAULT
      @vcd["control"]["retries"]["upload_vapp_files"] ||= RETRIES_UPLOAD_VAPP_FILES
      @vcd["control"]["retries"]["cpi"] ||= RETRIES_CPI
      @vcd["control"]["delay"] ||= DELAY

      @vcd["control"]["time_limit_sec"] = {} unless @vcd["control"]["time_limit_sec"]
      @vcd["control"]["time_limit_sec"]["default"] ||= TIMELIMIT_DEFAULT
      @vcd["control"]["time_limit_sec"]["delete_vapp_template"] ||= TIMELIMIT_DELETE_VAPP_TEMPLATE
      @vcd["control"]["time_limit_sec"]["delete_vapp"] ||= TIMELIMIT_DELETE_VAPP
      @vcd["control"]["time_limit_sec"]["delete_media"] ||= TIMELIMIT_DELETE_MEDIA
      @vcd["control"]["time_limit_sec"]["instantiate_vapp_template"] ||= TIMELIMIT_INSTANTIATE_VAPP_TEMPLATE
      @vcd["control"]["time_limit_sec"]["recompose_vapp_template"] ||= TIMELIMIT_RECOMPOSE_VAPP_TEMPLATE
      @vcd["control"]["time_limit_sec"]["power_on"] ||= TIMELIMIT_POWER_ON
      @vcd["control"]["time_limit_sec"]["power_off"] ||= TIMELIMIT_POWER_OFF
      @vcd["control"]["time_limit_sec"]["undeploy"] ||= TIMELIMIT_UNDEPLOY
      @vcd["control"]["time_limit_sec"]["process_descriptor_vapp_template"] ||= TIMELIMIT_PROCESS_DESCRIPTOR_VAPP_TEMPLATE
      @vcd["control"]["time_limit_sec"]["http_request"] ||= TIMELIMIT_HTTP_REQUEST

      @vcd["control"]["backoff"] ||= BACKOFF

      @vcd["control"]["rest_throttle"] = {} unless @vcd["control"]["rest_throttle"]
      @vcd["control"]["rest_throttle"]["min"] ||= REST_THROTTLE_MIN
      @vcd["control"]["rest_throttle"]["max"] ||= REST_THROTTLE_MAX

      @vcd["debug"] = {} unless @vcd["debug"]
      @vcd["debug"]["delete_vapp"]       ||= DEBUG_DELETE_VAPP
      @vcd["debug"]["delete_vm"]         ||= DEBUG_DELETE_VM
      @vcd["debug"]["delete_empty_vapp"] ||= DELETE_EMPTY_VAPP
    end

    def create_client
      url = @vcd["url"]
      @logger.debug("Create session to VCD cloud: #{url}")

      @client = VCloudSdk::Client.new(url, @vcd["user"],
        @vcd["password"], @vcd["entities"], @vcd["control"])

      @logger.info("Created session to VCD cloud: #{url}")

      @client
    rescue VCloudSdk::ApiError => e
      log_exception(e, "Failed to connect and establish session.")
      raise e
    end

    def destroy_client
      url = @vcd["url"]
      @logger.debug("Destroy session to VCD cloud: #{url}")
      # TODO VCloudSdk::Client should permit logout.
      @logger.info("Destroyed session to VCD cloud: #{url}")
    end

    def generate_unique_name
      SecureRandom.uuid
    end

    def log_exception(op, e)
      @logger.error("Failed to #{op}.")
      @logger.error(e)
    end

    def generate_network_env(nics, networks)
      nic_net = {}
      nics.each do |nic|
        nic_net[nic.network] = nic
      end
      @logger.debug("nic_net #{nic_net.inspect}")

      network_env = {}
      networks.each do |network_name, network|
        network_entry = network.dup
        v_network_name = network["cloud_properties"]["name"]
        nic = nic_net[v_network_name]
        if nic.nil? then
          @logger.warn("Not generating network env for #{v_network_name}")
          next
        end
        network_entry["mac"] = nic.mac_address
        network_env[network_name] = network_entry
      end
      network_env
    end

    def generate_disk_env(system_disk, ephemeral_disk)
      {
        "system" => system_disk.disk_id,
        "ephemeral" => ephemeral_disk.disk_id,
        "persistent" => {}
      }
    end

    def generate_agent_env(name, vm, agent_id, networking_env, disk_env)
      vm_env = {
        "name" => name,
        "id" => vm.urn
      }

      env = {}
      env["vm"] = vm_env
      env["agent_id"] = agent_id
      env["networks"] = networking_env
      env["disks"] = disk_env
      env.merge!(@agent_properties)
    end

    def get_current_agent_env(vm)
      env = @client.get_metadata(vm, @vcd["entities"]["vm_metadata_key"])
      @logger.info("Current agent env: #{env.inspect}")
      Yajl::Parser.parse(env)
    end

    def set_agent_env(vm, env)
      env_json = Yajl::Encoder.encode(env)
      @logger.debug("env.iso content #{env_json}")

      begin
        # Clear existing ISO if one exists.
        @logger.info("Ejecting ISO #{vm.name}")
        @client.eject_catalog_media(vm, vm.name)
        @logger.info("Deleting ISO #{vm.name}")
        @client.delete_catalog_media(vm.name)
      rescue VCloudSdk::ObjectNotFoundError
        @logger.debug("No ISO to eject/delete before setting new agent env.")
        # Continue setting agent env...
      end

      # generate env iso, and insert into VM
      Dir.mktmpdir do |path|
        env_path = File.join(path, "env")
        iso_path = File.join(path, "env.iso")
        File.open(env_path, "w") { |f| f.write(env_json) }
        output = `genisoimage -o #{iso_path} #{env_path} 2>&1`
        raise "#{$?.exitstatus} -#{output}" if $?.exitstatus != 0

        @client.set_metadata(vm, @vcd["entities"]["vm_metadata_key"], env_json)

        storage_profiles = @client.get_ovdc.storage_profiles || []
        media_storage_profile = storage_profiles.find { |sp| sp["name"] ==
          @vcd["entities"]["media_storage_profile"] }
        @logger.info("Uploading and inserting ISO #{iso_path} as #{vm.name} " +
          "to #{media_storage_profile.inspect}")
        @client.upload_catalog_media(vm.name, iso_path, media_storage_profile)
        @client.insert_catalog_media(vm, vm.name)
        @logger.info("Uploaded and inserted ISO #{iso_path} as #{vm.name}")
      end
    end

    def delete_vapp_networks(vapp, exclude_nets)
      exclude = exclude_nets.map { |k,v| v["cloud_properties"]["name"] }.uniq
      @client.delete_networks(vapp, exclude)
      @logger.debug("Deleted vApp #{vapp.name} networks excluding " +
        "#{exclude.inspect}.")
    end

    def add_vapp_networks(vapp, networks)
      @logger.debug("Networks to add: #{networks.inspect}")
      ovdc = @client.get_ovdc
      accessible_org_networks = ovdc.available_networks
      @logger.debug("Accessible Org nets: #{accessible_org_networks.inspect}")

      cloud_networks = networks.map { |k,v| v["cloud_properties"]["name"] }.uniq
      cloud_networks.each do |configured_network|
        @logger.debug("Adding configured network: #{configured_network}")
        org_net = accessible_org_networks.find {
          |n| n["name"] == configured_network }
        unless org_net
          raise VCloudSdk::CloudError, "Configured network: " +
            "#{configured_network}, is not accessible to VDC:#{ovdc.name}."
        end
        @logger.debug("Adding configured network: #{configured_network}, => " +
          "Org net:#{org_net.inspect} to vApp:#{vapp.name}.")
        @client.add_network(vapp, org_net)
        @logger.debug("Added vApp network: #{configured_network}.")
      end
      @logger.debug("Accessible configured networks added:#{networks.inspect}.")
    end

    def add_vm_nics(v, networks)
      networks.values.each_with_index do |network, nic_index|
        if nic_index + 1 >= VM_NIC_LIMIT then
          @logger.warn("Max number of NICs reached")
          break
        end
        configured_network = network["cloud_properties"]["name"]
        @logger.info("Adding NIC with IP address #{network["ip"]}.")
        v.add_nic(nic_index, configured_network,
          VCloudSdk::Xml::IP_ADDRESSING_MODE[:MANUAL], network["ip"])
        v.connect_nic(nic_index, configured_network,
          VCloudSdk::Xml::IP_ADDRESSING_MODE[:MANUAL], network["ip"])
      end
      @logger.info("NICs added to #{v.name} and connected to network:" +
                   " #{networks.inspect}")
    end

    def get_vm(vapp)
      vms = vapp.vms
      raise IndexError, "Invalid number of vApp VMs" unless vms.size == 1
      vms[0]
    end

    def get_vapp_vm_by_vapp_id(id)
      vapp = @client.get_vapp(id)
      [vapp, get_vm(vapp)]
    end

    def get_newly_added_disk(vm, disks_previous)
      disks_current = vm.hardware_section.hard_disks
      newly_added = disks_current - disks_previous

      if newly_added.size != 1
        @logger.debug("Previous disks in #{vapp_id}: #{disks_previous.inspect}")
        @logger.debug("Current disks in #{vapp_id}:  #{disks_current.inspect}")
        raise IndexError, "Expecting #{disks_previous.size + 1} disks, found " +
              "#{disks_current.size}"
      end

      @logger.info("Newly added disk: #{newly_added[0]}")
      newly_added[0]
    end

    def get_newly_added_vm(vapp, previous_vms)
      current_vms = vapp.vms
      newly_added = current_vms - previous_vms

      if newly_added.size != 1
        @logger.debug("Previous vms in #{vapp.id}: #{previous_vms.inspect}")
        @logger.debug("Current disks in #{vapp.id}:  #{current_vms.inspect}")
        raise IndexError, "Expecting #{previous_vms.size + 1} vms, found " +
            "#{current_vms.size}"
      end

      @logger.info("Newly added vm: #{newly_added[0]}")
      newly_added[0]
    end

    def independent_disks(disk_locality)
      disk_locality ||= []
      @logger.info("Instantiate vApp accessible to disks: " +
                   "#{disk_locality.join(",")}")
      disks = []
      disk_locality.each do |disk_id|
        disks << @client.get_disk(disk_id)
      end
      disks
    end

  end

end
