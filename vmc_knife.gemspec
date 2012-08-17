
$:.unshift File.expand_path("../lib", __FILE__)

require 'vmc_knife/version'
raise 'BUILD_NUMBER undefined. Expecting the environment variable BUILD_NUMBER to contain some digits like 012.' unless ENV['BUILD_NUMBER']
spec = Gem::Specification.new do |s|
  s.name = "vmc_knife"
  s.version = "0.0.#{ENV['BUILD_NUMBER']}"
  s.author = "Intalio Pte"
  s.email = "hmalphettes@gmail.com"
  s.homepage = "http://intalio.com"
  s.description = s.summary = "Extensions for VMC the CLI of VMWare's Cloud Foundry"
  s.executables = %w(vmc_knife)

  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ["README.md", "LICENSE"]

  s.add_dependency "vmc", "~> 0.3.18"

  s.add_dependency "rest-client", ">= 1.6.1", "< 1.7.0"
  #s.add_development_dependency "rake"
  s.add_development_dependency "rspec",   "~> 1.3.0"
  s.add_development_dependency "webmock", "= 1.5.0"

  s.bindir  = "bin"
  s.require_path = 'lib'
  s.files = %w(LICENSE README.md) + Dir.glob("{lib}/**/*")
end
