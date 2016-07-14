require 'spec_helper'
require 'yaml'
require 'tempfile'

describe "the vcloud_cpi executable" do
  it 'will return an appropriate error message when passed an invalid config file' do
    config_file = Tempfile.new('cloud_properties.yml')
    config_file.write({}.to_yaml)
    config_file.close

    command_file = Tempfile.new('command.json')
    command_file.write({'method'=>'ping', 'arguments'=>[], 'context'=>{'director_uuid' => 'abc123'}}.to_json)
    command_file.close

    stdoutput = `bin/vcloud_cpi #{config_file.path} < #{command_file.path} 2> /dev/null`
    status = $?.exitstatus

    expect(status).to eq(0)
    result = JSON.parse(stdoutput)

    expect(result.keys).to eq(%w(result error log))

    expect(result['result']).to be_nil

    expect(result['error']).to eq({
      'type' => 'Unknown',
      'message' => 'Could not find cloud properties in the configuration',
      'ok_to_retry' => false
    })

    expect(result['log']).to include('backtrace')
  end

  describe "#calculate_vm_cloud_properties" do

    let(:cloud_properties) do
      {
        'cloud' => {
          'properties' => {
            'agent' => {},
            'vcds' => [{
              'url' => '',
              'user' => '',
              'password' => '',
              'entities' => {
                'organization' => '',
                'virtual_datacenter' => '',
                'vapp_catalog' => '',
                'media_catalog' => '',
                'media_storage_profile' => '',
                'vapp_storage_profile' => '',
                'vm_metadata_key' => '',
                'description' => 'BOSH on vCloudDirector',
              }
            }]
          }
        }
      }
    end

    it 'maps cloud agnostic properties to vcloud specific properties' do
      config_file = Tempfile.new('cloud_properties.yml')
      config_file.write(cloud_properties.to_yaml)
      config_file.close

      command_file = Tempfile.new('command.json')
      command_file.write({'method'=>'calculate_vm_cloud_properties', 'arguments'=>[{'ram'=> 123, 'cpu'=> 1, 'ephemeral_disk_size'=> 1}], 'context'=>{'director_uuid' => 'abc123'}}.to_json)
      command_file.close

      stdoutput = `bin/vcloud_cpi #{config_file.path} < #{command_file.path} 2> /dev/null`
      status = $?.exitstatus

      expect(status).to eq(0)
      result = JSON.parse(stdoutput)

      expect(result.keys).to eq(%w(result error log))

      expect(result['error']).to be_nil

      expect(result['result']).to eq({
        'ram' => 123,
        'cpu' => 1,
        'disk' => 1
      })
    end
  end
end
