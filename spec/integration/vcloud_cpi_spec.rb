require_relative '../../tasks/common'

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
