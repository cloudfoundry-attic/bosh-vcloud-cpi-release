require_relative '../../tasks/common'
require_relative '../../lib/cloud/vcloud/steps/poweron'
require_relative '../../lib/cloud/vcloud/steps/instantiate'

describe 'vCloud CPI' do

  before :all do
    @target = CpiHelper::Target.new ENV['TEST_SETTINGS']
    @cfg = @target.cfg
    @logger = @target.logger

    if @cfg
      @template_id = ENV['TEMPLATE'] || @cfg['template']
      @image = nil
      if @template_id
        @template_id = @target.resolve_name @template_id
      else
        @image = @cfg['image']
        cpi = @target.new_cpi
        @logger.info "create_stemcell(#{@image})"
        @template_id = cpi.create_stemcell @image, nil
        @template_id.should_not be_nil
      end
      @logger.info "stemcell id: #{@template_id}"
    end
  end

  after :all do
    if !ENV['KEEP_TEMPLATE'] && @image
      cpi = @target.new_cpi
      @logger.info "delete_stemcell(#{@template_id})"
      cpi.delete_stemcell @template_id
    end
  end

  before :each do
    @cpi = @target.new_cpi
  end

  def test_configure(name)
    @conf = @cfg['tests'][name]
    @resource_pool = @conf['resource_pool']
    @network = { 'ip' => nil, 'cloud_properties' => { 'name' => @conf['network'] } }
    @networks = {}
    @networks[@conf['network']] = @network
  end

  context "when there is no error in create_vm" do
    it 'basic', :type => 'integration', :slow => true do
      pending 'Integration test disabled without TEST_SETTINGS' unless @cpi

      test_configure 'basic'

      vms = []
      @conf['vms'].each do |vm|
        @network['ip'] = vm['ip']
        @logger.info "create_vm(#{vm['name']}, #{@template_id}, #{@resource_pool.inspect}, #{@networks.inspect}, #{vm['disk-locality']}, #{vm['env']})"
        vm_id = @cpi.create_vm vm['name'], @template_id, @resource_pool, @networks, vm['disk-locality'], vm['env']
        vm_id.should_not be_nil
        vms << vm_id
        @logger.info "vm[#{vm['name']}] id: #{vm_id}"
        has_vm = @cpi.has_vm? vm_id
        has_vm.should be_true
        if vm['ip2']
          @network['ip'] = vm['ip2']
          @logger.info "configure_networks(#{vm_id}, #{@networks.inspect})"
          @cpi.configure_networks vm_id, @networks
        end
        if vm['disk']
          size = vm['disk']['size'].to_i
          locality = vm['disk']['locality'] ? vm_id : nil
          @logger.info "create_disk(#{size}, #{locality})"
          disk_id = @cpi.create_disk size, locality
          disk_id.should_not be_nil
          @logger.info "attach_disk(#{vm_id}, #{disk_id})"
          @cpi.attach_disk vm_id, disk_id
          @logger.info "detach_disk(#{vm_id}, #{disk_id})"
          @cpi.detach_disk vm_id, disk_id
          @logger.info "delete_disk(#{disk_id})"
          @cpi.delete_disk disk_id
        end
        if vm['reboot']
          @logger.info "reboot_vm(#{vm_id})"
          @cpi.reboot_vm vm_id
        end
      end

      has_vm = @cpi.has_vm? @template_id
      has_vm.should_not be_true

      vms.each do |vm_id|
        @logger.info "delete_vm(#{vm_id})"
        @cpi.delete_vm vm_id
        has_vm = @cpi.has_vm? vm_id
        has_vm.should_not be_true
      end
    end

    it 'concurrent', :type => 'integration', :slow => true do
      pending 'Integration test disabled without TEST_SETTINGS' unless @cpi

      test_configure 'concurrent'

      threads = []
      @conf['vms'].each_index do |index|
        vm = @conf['vms'][index]
        threads << Thread.new do
          network = @network.dup
          network['ip'] = vm['ip']
          networks = {}
          networks[network['cloud_properties']['name']] = network
          @logger.info "[#{index}:#{Thread.current.object_id.to_s(16)}] create_vm(#{vm['name']}, #{@template_id}, #{@resource_pool.inspect}, #{networks.inspect}, #{vm['disk-locality']}, #{vm['env']})"
          vm_id = @cpi.create_vm vm['name'], @template_id, @resource_pool, networks, vm['disk-locality'], vm['env']
          @logger.info "delete_vm(#{vm_id})"
          @cpi.delete_vm vm_id
        end
      end

      threads.each { |thread| thread.join }
    end
  end

  context "when received exception during create_vm" do
    context "when target vapp exists" do
      it 'the tmp vapp should be removed', :type => 'integration', :slow => true do
        pending 'Integration test disabled without TEST_SETTINGS' unless @cpi

        test_configure 'basic'

        vm = @conf['vms'][0]
        @network['ip'] = vm['ip']
        # First successfully create the target vapp
        @logger.info "create_vm(#{vm['name']}, #{@template_id}, #{@resource_pool.inspect}, #{@networks.inspect}, #{vm['disk-locality']}, #{vm['env']})"
        vm_id = @cpi.create_vm vm['name'], @template_id, @resource_pool, @networks, vm['disk-locality'], vm['env']
        vm_id.should_not be_nil

        vm = @conf['vms'][1]
        @network['ip'] = vm['ip']
        exceptionMsg = 'PowerOn Failed!'
        VCloudCloud::Steps::PowerOn.any_instance.stub(:perform).and_raise(exceptionMsg)

        @logger.info "create_vm(#{vm['name']}, #{@template_id}, #{@resource_pool.inspect}, #{@networks.inspect}, #{vm['disk-locality']}, #{vm['env']})"
        begin
          @cpi.create_vm vm['name'], @template_id, @resource_pool, @networks, vm['disk-locality'], vm['env']
          fail 'create_vm should fail'
        rescue => ex
          ex.to_s.should eq exceptionMsg
        end

        # The target vapp should exist despite that the tmp vapp is deleted
        vapp_name = vm['env']['vapp']
        @target.client.flush_cache  # flush cached vdc which contains vapp list
        vapp = @target.client.vapp_by_name vapp_name
        vapp.name.should eq vapp_name
        vapp.vms.size.should eq 2
        @logger.info "delete_vm(#{vm_id})"
        @cpi.delete_vm vm_id
        has_vm = @cpi.has_vm? vm_id
        has_vm.should_not be_true

        # Hack: if vApp is running, and the last VM is deleted, it is no longer stoppable and removable
        # even from dashboard. So if there's only one VM, just stop and delete the vApp
        # We don't need to poweroff vapp since its VM is already poweroff
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'UndeployVAppParams'
        @target.client.invoke_and_wait :post, vapp.undeploy_link, :payload => params
        link = vapp.remove_link true
        @target.client.invoke_and_wait :delete, link
      end
    end

    context "when target vapp does not exist" do
      it 'the tmp vapp should not exist', :type => 'integration', :slow => true do
        pending 'Integration test disabled without TEST_SETTINGS' unless @cpi

        test_configure 'basic'

        vm = @conf['vms'][0]
        @network['ip'] = vm['ip']
        exceptionMsg = 'PowerOn Failed!'
        VCloudCloud::Steps::PowerOn.any_instance.stub(:perform).and_raise(exceptionMsg)

        begin
          @logger.info "create_vm(#{vm['name']}, #{@template_id}, #{@resource_pool.inspect}, #{@networks.inspect}, #{vm['disk-locality']}, #{vm['env']})"
          @cpi.create_vm vm['name'], @template_id, @resource_pool, @networks, vm['disk-locality'], vm['env']
          fail 'create_vm should fail'
        rescue => ex
          ex.to_s.should eq exceptionMsg
        end

        # The tmp vapp is renamed to the target vapp
        vapp_name = vm['env']['vapp']
        @target.client.flush_cache  # flush cached vdc which contains vapp list
        vapp = @target.client.vapp_by_name vapp_name
        vapp.name.should eq vapp_name
        @target.client.invoke_and_wait :delete, vapp.remove_link

        vm = @conf['vms'][1]
        @network['ip'] = vm['ip']
        exceptionMsg = 'Recompose Failed!'
        VCloudCloud::Steps::Recompose.any_instance.stub(:perform).and_raise(exceptionMsg)

        begin
          # The tmp vapp is not renamed to the target because recomposing failed
          # Instantiate rollback will delete the tmp vapp
          @logger.info "create_vm(#{vm['name']}, #{@template_id}, #{@resource_pool.inspect}, #{@networks.inspect}, #{vm['disk-locality']}, #{vm['env']})"
          @cpi.create_vm vm['name'], @template_id, @resource_pool, @networks, vm['disk-locality'], vm['env']
          fail 'create_vm should fail'
        rescue => ex
          ex.to_s.should eq exceptionMsg
        end
      end
    end
  end
end
