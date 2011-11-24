require 'spec_helper'
require 'tmpdir'
require 'vmc_knife'

describe 'VMC::KNIFE' do

  it 'should load the recipe object model' do
    root_file = spec_asset('tests/intalio_recipe.json')
    root = load_root(root_file)
    root.should
  end
  
  it 'should find some values, data services and applications manifests' do
    root_file = spec_asset('tests/intalio_recipe.json')
    root = load_root(root_file)
    root.sub_domain.should == "intalio.local"
    root.recipe('intalio_recipe').should
    root.recipe('intalio_recipe').application('intalio').name.should == "intalio"
    root.recipe('intalio_recipe').application('intalio').uris[0].should == "intalio.local"
  end
  
  it 'should get/set/del/add environment variables' do
    root_file = spec_asset('tests/intalio_recipe.json')
    root = load_root(root_file)
    root.sub_domain.should == "intalio.local"
    root.recipe('intalio_recipe').should
    intalio = root.recipe('intalio_recipe').application('intalio')
    env = intalio.env
    env.should
    env.get('INTALIO_AUTH').should == "http://oauth.intalio.local"
    env.get('FOO').should == nil
    env.set('FOO',"bar")
    env.get('FOO').should == "bar"
    env.set('FOO',"joe")
    env.get('FOO').should == "joe"
    env.set('FOO',"bar\=joe")
    env.get('FOO').should == "bar=\joe"
    env.del('FOO')
    env.get('FOO').should == nil
  end
  
  it 'should compute the pending udpates for an application manifest' do
    current = spec_asset('tests/vmc_app_oauth.json')
    recipe = spec_asset('tests/intalio_recipe.json')
    man = load_root(recipe)
    oauth_update = man.recipe('intalio_recipe').application('oauth')
    configure_oauth = VMC::KNIFE::ApplicationManifestApplier.new(oauth_update, nil)
    configure_oauth.__set_current(JSON.parse File.open(current).read)
    diff = configure_oauth.updates_pending()
    puts JSON.pretty_generate diff
    diff.size.should ==1
    diff['uris'].should
    diff['uris']['add'].should == ["oauth.intalio.local"]
    diff['uris']['remove'].should == ["oauth.vcap.me"]
  end

  def load_root json_file_path
    VMC::KNIFE::Root.new json_file_path
  end

end
