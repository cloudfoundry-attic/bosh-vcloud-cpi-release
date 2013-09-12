describe 'vCloud Stress Deploy' do
  def stress_deploy(levels, factor)
    raise 'STRESS_DIRECTOR not set' unless ENV['STRESS_DIRECTOR']
    raise 'STRESS_MANIFEST not set' unless ENV['STRESS_MANIFEST']
    raise 'STRESS_BASE_IP not set' unless ENV['STRESS_BASE_IP']
    `bin/stress-deploy #{ENV['STRESS_DIRECTOR']} #{ENV['STRESS_MANIFEST']} #{ENV['STRESS_BASE_IP']} #{levels} #{factor}`
    raise 'Script failed #{$?.exitstatus}' if $?.existstatus != 0
  end

  it "deploy 2x2" do
    stress_deploy 2 2
  end

  it "deploy 2x4" do
    stress_deploy 4 2
  end

  it "deploy 4x2" do
    stress_deploy 2 4
  end

  it "deploy 8x2" do
    stress_deploy 2 8
  end
  
end
