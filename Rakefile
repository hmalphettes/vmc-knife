require "rubygems"
require "rspec/core/rake_task"

spec_opts = %w{--colour --format progress}

begin
  desc "Run the specs"
  task :spec do
    RSpec::Core::RakeTask.new(:spec) do |t|
      t.rspec_opts = spec_opts
      # Add more specs please....
      t.pattern = 'spec/units/data_services_spec.rb'
    end
  end
rescue LoadError
    task :spec do
      abort "Rspec/Rack-test is not available. In order to run rack-test, you must: (sudo) gem install rack-test"
    end
end


