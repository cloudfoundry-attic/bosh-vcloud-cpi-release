module VCloudSdk
  module Xml

    class VApp < Wrapper
      def description
        get_nodes("Description").first.content
      end

      def network_config_section
        get_nodes("NetworkConfigSection").first
      end

      def power_on_link
        get_nodes("Link", {"rel" => "power:powerOn"}, true).first
      end

      def power_off_link
        get_nodes("Link", {"rel" => "power:powerOff"}, true).first
      end

      def reboot_link
        get_nodes("Link", {"rel" => "power:reboot"}, true).first
      end

      def cancel_link
        get_nodes("Link", {"rel" => "task:cancel"}, true).first
      end

      def remove_link(force = false)
        link = get_nodes("Link", {"rel" => "remove"}, true).first
        return link if !force

        fix_if_invalid(link, "remove", "", href)
      end

      def running_tasks
        get_nodes("Task", {"status" => "running"})
      end

      def tasks
        get_nodes("Task")
      end

      def undeploy_link(force = false)
        link = get_nodes("Link", {"rel" => "undeploy"}, true).first
        return link if !force

        fix_if_invalid(link,
                       "undeploy",
                       MEDIA_TYPE[:UNDEPLOY_VAPP_PARAMS],
                       "#{href}/action/undeploy")
      end

      def discard_state
        get_nodes("Link", {"rel" => "discardState"}, true).first
      end

      def recompose_vapp_link(force = false)
        link = get_nodes("Link", {"rel" => "recompose"}, true).first
        return link if !force

        fix_if_invalid(link,
                       "recompose",
                       MEDIA_TYPE[:RECOMPOSE_VAPP_PARAMS],
                       "#{href}/action/recomposeVApp")
      end

      def vms
        get_nodes("Vm")
      end

      def vm(name)
        get_nodes("Vm", {"name" => name}).first
      end
    end
  end
end
