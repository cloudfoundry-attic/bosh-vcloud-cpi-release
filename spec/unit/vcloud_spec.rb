require "spec_helper"

describe Bosh::Clouds::VCloud do
  it 'has all methods of the cpi' do
    cpi_methods = Bosh::Cloud.instance_methods - Object.instance_methods
    vcloud_methods = described_class.instance_methods - Object.instance_methods
    # skip the APIs that vcloud doesn't suport
    unsupported_methods = [:current_vm_id, :delete_snapshot, :has_disk?,
                           :get_disks, :set_vm_metadata, :snapshot_disk]
    missing_methods = cpi_methods - vcloud_methods - unsupported_methods

    # this causes the extra elements to be printed on console
    expect(missing_methods).to match_array([])
  end
end
