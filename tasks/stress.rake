require 'fileutils'

namespace :stress do
  desc 'prepare release'
  task 'prepare_release', :bosh_src do |_, args|
    release_dir = File.join File.dirname(__FILE__), '../spec/stress/release'
    src_dir = File.join release_dir, 'src'
    vendor_cache = File.join src_dir, 'bosh-cli/vendor/cache'
    FileUtils.mkdir_p vendor_cache
    FileUtils.cp_r Dir.glob(File.join(args[:bosh_src], 'vendor/cache/*.gem')), vendor_cache
    ['bosh_cli', 'bosh_common', 'blobstore_client'].each do |prefix|
      FileUtils.cp Dir.glob(File.join(args[:bosh_src], 'pkg', 'gems', "#{prefix}-*.gem")), vendor_cache
    end
    FileUtils.mkdir_p File.join(src_dir, 'ruby')
    FileUtils.cp_r Dir.glob(File.join(args[:bosh_src], 'release/src/ruby/*')), File.join(src_dir, 'ruby')
  end
end