require 'yaml'
require_relative 'common'

module VCloud
  class Diagnose
    def initialize(target)
      @target = CpiHelper::Target.new(target || ENV['TARGET'])
    end

    def client
      @target.client
    end

    def catalogs
      catalogs = client.org.get_nodes 'Link', {'type' => 'application/vnd.vmware.vcloud.catalog+xml'}
      if catalogs && catalogs.any?
        catalog = catalogs.each do |catalog_link|
          catalog = nil
          error_ignored { catalog = client.resolve_link catalog_link }
          if catalog
            text_block 0, <<-EOF
                Catalog: #{catalog.name}
                  URN : #{catalog.urn}
                  HREF: #{catalog.href}
                  ITEMS:
              EOF
            catalog.catalog_items.each do |item_link|
              error_ignored do
                item = client.resolve_link item_link
                text_block 4, <<-EOF
                    ITEM: #{item.name}
                      URN : #{item.urn}
                      HREF: #{item.href}
                  EOF
              end
            end
          end
        end
      end
    end

    def vms
      vapps = client.vdc.get_nodes 'ResourceEntity', {'type' => 'application/vnd.vmware.vcloud.vApp+xml'}
      raise 'No vApp available' if !vapps or vapps.empty?
      vapp = vapps.each do |vapp_entity|
        error_ignored do
          vapp = client.resolve_link vapp_entity.href
          owners = vapp.get_nodes 'User', { 'type' => 'application/vnd.vmware.admin.user+xml' }
          text_block 0, <<-EOF
            vApp: #{vapp.name}
              URN : #{vapp.urn}
              HREF: #{vapp.href}"
              STAT: #{vapp['status']}
              OWNR: #{resolve_owner(vapp)}
              VMS :
          EOF
          vapp.vms.each do |vm|
            text_block 4, <<-EOF
              VM: #{vm.name}
                URN : #{vm.urn}
                HREF: #{vm.href}
                STAT: #{vm['status']}
            EOF
          end
        end
      end
    end

    def disks
      entities = client.vdc.disks || []
      entities.each do |disk_entity|
        disk = nil
        error_ignored { disk = client.resolve_link disk_entity }
        if disk
          text_block 0, <<-EOF
            Disk: #{disk.name}
              URN : #{disk.urn}
              HREF: #{disk.href}
              OWNR: #{resolve_owner(disk)}
              SIZE: #{disk['size']}
              BUS : #{disk['busType']}
              SBUS: #{disk['busSubType']}
          EOF
        end
      end
    end

    def clear(owner, catalog)
      raise 'Owner must be specified' unless owner

      puts "Cleaning for owner #{owner}"

      clean_entities owner, 'application/vnd.vmware.vcloud.vApp+xml' do |vapp|
        if vapp.vms
          vapp.vms.each do |vm|
            error_ignored { poweroff vm }
          end
        end
        error_ignored { poweroff vapp }
      end

      ['application/vnd.vmware.vcloud.media+xml',
       'application/vnd.vmware.vcloud.disk+xml',
       'application/vnd.vmware.vcloud.vAppTemplate+xml'].each do |type|
        clean_entities owner, type
      end

      clean_catalog catalog if catalog
    end

    private

    def text_block(indent, lines)
      prefix = ''
      indent.times { prefix += ' ' }
      lines = lines.split "\n"
      len = nil
      lines.each do |line|
        m = line.match %r/^\s+/
        len = m[0].length if len.nil? || len > m[0].length
      end
      puts lines.map { |line| prefix + line[len..-1] }.join("\n")
    end

    def error_ignored
      yield
    rescue RestClient::Exception => ex
      puts "RestClient exception: #{ex}: #{ex.response.body}"
    rescue => ex
      puts "Ignored #{ex}"
    end

    def resolve_owner(object, default_name = nil)
      owners = object.get_nodes 'User', { 'type' => 'application/vnd.vmware.admin.user+xml' }
      owners && owners.any? ? owners[0].name : default_name
    end

    def force_link(object, rel)
      link = object.get_nodes('Link', {'rel' => rel}, true).first
      if link.nil? || link.href.to_s.nil?
        link = VCloudSdk::Xml::WrapperFactory.create_instance 'Link'
        link.rel  = rel
        link.type = ""
        link.href = object.href
      end
      link
    end

    def clean_entities(owner, type, &block)
      (client.vdc.get_nodes('ResourceEntity', { 'type' => type }) || []).each do |entity|
        error_ignored do
          puts "Checking #{entity.name}: #{entity.href}"
          object = client.resolve_link entity
          users = object.get_nodes('User', { 'type' => 'application/vnd.vmware.admin.user+xml' }) || []
          user = users[0]
          puts "Object owner: #{user ? user.name : ''}"
          if user && user.name == owner
            block.call(object) if block
            puts "Deleting #{object.name}(#{object.urn}) of #{type}"
            client.invoke_and_wait :delete, force_link(object, 'remove')
          end
        end
      end
    end

    def poweroff(object)
      object = client.reload object
      if object['status'] == VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:SUSPENDED].to_s
        puts "Discarding suspend state of #{object.name}"
        client.invoke_and_wait :post, object.discard_state
        object = client.reload object
      end
      if object['status'] != VCloudSdk::Xml::RESOURCE_ENTITY_STATUS[:POWERED_OFF].to_s
        puts "Powering off #{object.name}"
        poweroff_link = object.power_off_link
        unless poweroff_link
          puts "#{object.name} unable to power off, forced"
          poweroff_link = force_link(object, 'power:powerOff')
        end
        client.invoke_and_wait :post, poweroff_link
        object = client.reload object
      end
      if object['deployed'] == 'true'
        puts "Undeploying #{object.name}"
        link = object.undeploy_link
        unless link
          puts "#{object.name} can't be undeployed, forced"
          link = force_link(object, 'undeploy')
        end
        params = VCloudSdk::Xml::WrapperFactory.create_instance 'UndeployVAppParams'
        client.invoke_and_wait :post, link, :payload => params
      end
      object
    end

    def clean_catalog(name)
      nodes = client.org.get_nodes 'Link', {'type' => 'application/vnd.vmware.vcloud.catalog+xml', 'name' => name}
      return if !nodes or nodes.empty?
      nodes.each do |catalog_link|
        error_ignored do
          catalog = client.resolve_link catalog_link
          catalog.catalog_items.each do |item_link|
            error_ignored do
              item = client.resolve_link item_link
              puts "Deleting Catalog Item #{item.name}(#{item.urn})"
              client.invoke_and_wait :delete, force_link(item, 'remove')
            end
          end
        end
      end
    end
  end
end

namespace :diag do
  desc 'list catalog items'
  task 'catalogs', :target do |_, args|
    VCloud::Diagnose.new(args[:target]).catalogs
  end

  desc 'list virtual machines'
  task 'vms', :target do |_, args|
    VCloud::Diagnose.new(args[:target]).vms
  end

  desc 'list disks'
  task 'disks', :target do |_, args|
    VCloud::Diagnose.new(args[:target]).disks
  end

  desc 'clear everything!!!'
  task 'clear', :target, :owner, :catalog do |_, args|
    VCloud::Diagnose.new(args[:target]).clear args[:owner], args[:catalog]
  end
end