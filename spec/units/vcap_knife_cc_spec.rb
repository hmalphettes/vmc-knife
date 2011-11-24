require 'spec_helper'
require 'tmpdir'
require 'vmc_knife'
require 'yaml'

describe 'VMC::KNIFE' do

  it 'should load reconfigure the cloudcontroller config file' do
    cc_config = spec_asset('tests/cloud_controller.yml')
    cc_yml = File.open( cc_config ) { |yf| YAML::load( yf ) }
    cc_yml['external_uri'].should == "api.vcap.local"
    update_cc = VMC::KNIFE::VCAPUpdateCloudControllerConfig.new("api.foo.local",cc_config)
    update_cc.update_pending().should
    update_cc.execute()
    update_cc.was_changed().should
    cc_yml = File.open( cc_config ) { |yf| YAML::load( yf ) }
    cc_yml['external_uri'].should == "api.foo.local"
    update_cc = VMC::KNIFE::VCAPUpdateCloudControllerConfig.new("api.vcap.local",cc_config)
    update_cc.update_pending().should
    update_cc.execute()
    update_cc.was_changed().should
    cc_yml = File.open( cc_config ) { |yf| YAML::load( yf ) }
    cc_yml['external_uri'].should == "api.vcap.local"
  end
  
  it 'should load reconfigure the /etc/hosts file' do
    cc_config = spec_asset('tests/etc_hosts')
    `grep api.vcap.local #{cc_config}`.should
    update_eh = VMC::KNIFE::VCAPUpdateEtcHosts.new("api.foo.local",cc_config)
    update_eh.update_pending().should
    update_eh.execute()
    update_eh.was_changed().should
    `grep api.foo.local #{cc_config}`.should
    update_cc = VMC::KNIFE::VCAPUpdateEtcHosts.new("api.vcap.local",cc_config)
    update_cc.update_pending().should
    update_cc.execute()
    update_cc.was_changed().should
    `grep api.vcap.local #{cc_config}`.should
  end
  
  it 'should load reconfigure the /etc/avahi/aliases file' do
    etc_avahi_aliases = spec_asset('tests/etc_avahi_aliases')
    FileUtils.cp etc_avahi_aliases, "/tmp/etc_avahi_aliases.tmp"
    begin
      recipe = spec_asset('tests/intalio_recipe.json')
      update_aliases = VMC::KNIFE::VCAPUpdateAvahiAliases.new(etc_avahi_aliases,recipe,nil)
      existing = update_aliases.already_published_uris
      existing.include?("simple.vcap.local").should
      to_publish=update_aliases.all_uris
      to_publish.length.should >= 3
      update_aliases.update_pending().should
      update_aliases.execute()
      update_aliases = VMC::KNIFE::VCAPUpdateAvahiAliases.new(etc_avahi_aliases,recipe,nil)
      existing = update_aliases.already_published_uris
      existing.should == to_publish    
    ensure 
      FileUtils.cp("/tmp/etc_avahi_aliases.tmp", etc_avahi_aliases)
    end
  end
 

end
