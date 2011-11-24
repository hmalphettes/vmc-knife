require 'spec_helper'
require 'tmpdir'
require 'vmc_knife'

#humf in progress and not so useful.
describe 'VMC::KNIFE::JSON_DIFF' do

  it 'should be able to load the diff of 2 json' do
    a = spec_asset('tests/vmc_app_oauth.json')
    b = spec_asset('tests/vmc_app_oauth2.json')
    diff = diff_json(a,b)
    puts diff
  end
  
  def diff_json(a,b)
    VMC::KNIFE::JSON_DIFF.compare(a,b)
  end

end
