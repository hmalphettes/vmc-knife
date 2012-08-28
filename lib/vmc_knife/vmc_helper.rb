require 'json'
require 'cli/frameworks'
# add java_start our own framework to the array of well known frameworks
VMC::Cli::Framework::FRAMEWORKS['JavaGen'] = ['java_start',{ :mem => '512M', :description => 'Java Custom Application'}]

module VMC
  module KNIFE
    module HELPER
    
  def self.static_upload_app_bits(client,appname, path)
      display "Uploading Application #{appname} from #{path}:"

      upload_file, file = "#{Dir.tmpdir}/#{appname}.zip", nil
      FileUtils.rm_f(upload_file)

      explode_dir = "#{Dir.tmpdir}/.vmc_#{appname}_files"
      FileUtils.rm_rf(explode_dir) # Make sure we didn't have anything left over..

      Dir.chdir(path) do
        # Stage the app appropriately and do the appropriate fingerprinting, etc.
        if war_file = Dir.glob('*.war').first
puts "Exploding the war"
          VMC::Cli::ZipUtil.unpack(war_file, explode_dir)
puts "Done Exploding the war"
        else
puts "Copying the files"
          FileUtils.mkdir(explode_dir)
          files = Dir.glob('{*,.[^\.]*}')
          # Do not process .git files
          files.delete('.git') if files
          FileUtils.cp_r(files, explode_dir)
puts "Done copying the files"
        end

        # Send the resource list to the cloudcontroller, the response will tell us what it already has..
###        unless @options[:noresources]
          display '  Checking for available resources: ', false
          fingerprints = []
          total_size = 0
puts "About to compute the fingerprints"
          resource_files = Dir.glob("#{explode_dir}/**/*", File::FNM_DOTMATCH)
          resource_files.each do |filename|
            next if (File.directory?(filename) || !File.exists?(filename))
            fingerprints << {
              :size => File.size(filename),
              :sha1 => Digest::SHA1.file(filename).hexdigest,
              :fn => filename
            }
            total_size += File.size(filename)
          end
puts "Finished computing the fingerprints"
          # Check to see if the resource check is worth the round trip
          if (total_size > (64*1024)) # 64k for now
            # Send resource fingerprints to the cloud controller
puts "Invoking check_resources with the fingerprints"
            appcloud_resources = client.check_resources(fingerprints)
          end
          display 'OK'.green

          if appcloud_resources
            display '  Processing resources: ', false
            # We can then delete what we do not need to send.
            appcloud_resources.each do |resource|
              FileUtils.rm_f resource[:fn]
              # adjust filenames sans the explode_dir prefix
              resource[:fn].sub!("#{explode_dir}/", '')
            end
            display 'OK'.green
          end

###        end

        # Perform Packing of the upload bits here.
        unless VMC::Cli::ZipUtil.get_files_to_pack(explode_dir).empty?
          display '  Packing application: ', false
          VMC::Cli::ZipUtil.pack(explode_dir, upload_file)
          display 'OK'.green

          upload_size = File.size(upload_file);
          if upload_size > 1024*1024
            upload_size  = (upload_size/(1024.0*1024.0)).round.to_s + 'M'
          elsif upload_size > 0
            upload_size  = (upload_size/1024.0).round.to_s + 'K'
          end
        else
          upload_size = '0K'
        end

        upload_str = "  Uploading (#{upload_size}): "
        display upload_str, false

        unless VMC::Cli::ZipUtil.get_files_to_pack(explode_dir).empty?
          VMC::Cli::Command::FileWithPercentOutput.display_str = upload_str
          VMC::Cli::Command::FileWithPercentOutput.upload_size = File.size(upload_file);
          file = VMC::Cli::Command::FileWithPercentOutput.open(upload_file, 'rb')
        end
puts "client.upload_app about to start"
        retries = 5
        begin
          client.upload_app(appname, file, appcloud_resources)
        rescue Exception => e
          retry if (retries -= 1) > 0
        end
puts "Done client.upload_app"
        display 'OK'.green if VMC::Cli::ZipUtil.get_files_to_pack(explode_dir).empty?

        display 'Push Status: ', false
        display 'OK'.green
      end

    ensure
      # Cleanup if we created an exploded directory.
      FileUtils.rm_f(upload_file) if upload_file
      FileUtils.rm_rf(explode_dir) if explode_dir
    end
    
    end # end of HELPER
  end # end of KNIFE
end
