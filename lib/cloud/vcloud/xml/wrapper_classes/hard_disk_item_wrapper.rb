module VCloudSdk
  module Xml

    class HardDiskItemWrapper < Item
      def hash
        [disk_id, instance_id, bus_type, bus_sub_type].hash
      end

      def eql?(other)
        disk_id == other.disk_id && instance_id == other.instance_id &&
          bus_type == other.bus_type && bus_sub_type == other.bus_sub_type
      end

      def initialize(item)
        super(item.node, item.namespace, item.namespace_definitions)
      end

      def disk_id
        get_rasd_content(RASD_TYPES[:ADDRESS_ON_PARENT])
      end

      def instance_id
        get_rasd_content(RASD_TYPES[:INSTANCE_ID])
      end

      def capacity_mb
        v = host_resource.attribute_with_ns(
            VCloudSdk::Xml::HOST_RESOURCE_ATTRIBUTE[:CAPACITY],
            VCloudSdk::Xml::VCLOUD_NAMESPACE)
        return v.nil? ? nil : v.value
      end

      def disk_href
        v = host_resource.attribute_with_ns(
            VCloudSdk::Xml::HOST_RESOURCE_ATTRIBUTE[:DISK],
            VCloudSdk::Xml::VCLOUD_NAMESPACE)
        return v.nil? ? nil : v.value
      end

      def bus_sub_type
        v = host_resource.attribute_with_ns(
            VCloudSdk::Xml::HOST_RESOURCE_ATTRIBUTE[:BUS_SUB_TYPE],
            VCloudSdk::Xml::VCLOUD_NAMESPACE)
        return v.nil? ? nil : v.value
      end

      def bus_type
        v = host_resource.attribute_with_ns(
            VCloudSdk::Xml::HOST_RESOURCE_ATTRIBUTE[:BUS_TYPE],
            VCloudSdk::Xml::VCLOUD_NAMESPACE)
        return v.nil? ? nil : v.value
      end

      def parent_instance_id
        get_rasd_content(RASD_TYPES[:PARENT])
      end

      def host_resource
        get_rasd(RASD_TYPES[:HOST_RESOURCE])
      end
    end

  end
end
