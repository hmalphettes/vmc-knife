require 'spec_helper'
require 'vmc_knife'
require 'vmc_knife/data_services'
require 'zip/zipfilesystem'

module MockVMCKnife
  
  @@vmc_knife = RSpec::Mocks::Mock.new('vmc_knife')
  
  def self.get_vmc_knife
    @@vmc_knife
  end
  
end

module VMC::KNIFE
  
  def self.pg_connect_cmd(credentials_hash, executable='psql',as_admin=false, other_params="")
    puts "Fake connecting to pg_connect_cmd"
    MockVMCKnife.get_vmc_knife().pg_connect_cmd(credentials_hash, executable, as_admin)
    "echo"
  end
  
  def self.get_credentials(name, app_name)
    MockVMCKnife.get_vmc_knife().get_credentials(name, app_name)
    {}
  end
  
end

describe 'VMC::KNIFE::DataService' do

  it 'should be able to import a postgres export with sql in tar gz format' do
    name = 'pg_intalio'
    data_download_dir="#{ENV['HOME']}/vmc_knife_downloads/data_#{name}"
    archive_name = 'test_backup.tar.gz'
    archive_name2 = 'test_backup2.tar.gz'
    dump_file = "dump.sql"
    vmc_knife = MockVMCKnife.get_vmc_knife()
    vmc_knife.should_receive(:pg_connect_cmd).exactly(3).times.with({}, 'psql', false)
    vmc_knife.should_receive(:get_credentials).once.with(name, nil)

    begin
      svc = VMC::KNIFE::DataService.new(nil, { 'name' => name }, nil)
      File.open(dump_file, "w") { |f| f.puts "" }
      `tar zcvf #{archive_name} #{dump_file}`
      
      svc.import('intalio', archive_name)
      # check that the archive exists in data dir
      File.exists?("#{data_download_dir}/#{archive_name}").should == true
      
      # import the second time to exercise the part of the code that 
      # avoids copying if archive already exists
      svc.import('intalio', archive_name)
      
      # import a third time with a different archive name
      # to check old archives are deleted correctly
      `tar zcvf #{archive_name2} #{dump_file}`
      svc.import('intalio', archive_name2)
      File.exists?("#{data_download_dir}/#{archive_name2}").should == true
      File.exists?("#{data_download_dir}/#{archive_name}").should == false
      Dir.entries(data_download_dir).size.should == 4
      
    ensure
      puts "Cleaning up all file artifacts"
      File.delete(dump_file) if File.exists?(dump_file)
      File.delete(archive_name) if File.exists?(archive_name)
      File.delete(archive_name2) if File.exists?(archive_name2)
      FileUtils.rm_rf(data_download_dir)
    end
  end
  
  
end