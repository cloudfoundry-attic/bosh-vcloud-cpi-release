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
end
