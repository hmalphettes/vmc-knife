
$:.unshift('./lib')
require 'bundler'
require 'bundler/setup'
require 'vmc_knife'
require 'cli'

require 'spec'

def spec_asset(filename)
  File.expand_path(File.join(File.dirname(__FILE__), "assets", filename))
end
