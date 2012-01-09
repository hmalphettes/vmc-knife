require 'spec_helper'
require 'tmpdir'
require 'vmc_knife'

describe 'VMC::KNIFE::JSON_EXPANDER' do

  it 'should be able to load simple.json as json' do
    recipe = spec_asset('tests/simple.json')
    exp_recipe = expand_json(recipe)
    puts JSON.pretty_generate exp_recipe
  end

  it 'should be able to load intalio_recipe.json as json' do
    recipe = spec_asset('tests/intalio_recipe.json')
    exp_recipe = expand_json(recipe)
    puts JSON.pretty_generate exp_recipe
  end

 
  it 'should evaluate the ruby embedded in the json values' do
    recipe = spec_asset('tests/intalio_recipe.json')
    exp_recipe = expand_json(recipe)
    exp_recipe['target'].should == "api.#{exp_recipe['sub_domain']}"
    exp_recipe['recipes'][0]['applications']['admin']['env'][0].should == "INTALIO_AUTH=http://oauth.#{exp_recipe['sub_domain']}"
    exp_recipe['recipes'][0]['applications']['intalio']['repository']['url'].should == "http://bob:secret@thedownload.com/download/it/1.0.0.123/intalio.war"
    exp_recipe['recipes'][0]['applications']['intalio']['services'].should == ["pg_intalio", "mg_intalio"]
    exp_recipe['recipes'][0]['applications']['oauth']['services'].should == ["pg_intalio", "mg_intalio"]
    exp_recipe['recipes'][0]['applications']['oauth']['uris'].should == ["oauth.intalio.local"]
    
  end

  def expand_json json_file_path
    VMC::KNIFE::JSON_EXPANDER.expand_json json_file_path
  end

end
