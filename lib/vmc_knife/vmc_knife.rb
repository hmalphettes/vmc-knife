require 'vmc/client'
require 'json'
require 'yaml'

module VMC
  module KNIFE
    
    # Read/Write the JSON for a recipe.
    # Does not map the actual JSON into a new ruby object.
    class Root
      attr_accessor :wrapped
      def initialize(data)
        if data.kind_of? Hash
          @wrapped = data
        elsif data.kind_of? String
          @wrapped = VMC::KNIFE::JSON_EXPANDER.expand_json data
        elsif data.kind_of? Root
          @wrapped = data.wrapped
        else
          raise "Unexpected data #{data}"
        end
      end
      def sub_domain()
        @wrapped['sub_domain']
      end
      def user()
        @wrapped['user']
      end
      def target()
        @wrapped['target']
      end
      def recipes(regexp=nil)
        regexp||=/.*/
        res = Array.new
        @wrapped['recipes'].each do |recipe|
          res << Recipe.new(self, recipe) if (regexp =~ recipe['name'])
        end
        res
      end
      def recipe(name)
        res = @wrapped['recipes'].select {|v| v['name'] == name}
        Recipe.new self, res.first unless res.empty?
      end
      def first_recipe(name)
        Recipe.new self, @wrapped['recipes'][0] unless @wrapped['recipes'].empty?
      end
      def to_json()
        @wrapped.to_json
      end
      
    end
    
    class Recipe
      attr_accessor :wrapped, :root
      # root: Root
      # data: The recipe's data. not the root of the json.
      def initialize(root,data)
        @wrapped = data
        @root = root
      end
      #An application.
      def application(name)
        Application.new @root, @wrapped['applications'][name], name
      end
      def applications(regexp=nil)
        regexp||=/.*/
        res = Array.new
        @wrapped['applications'].each_pair do |name,application|
          res << Application.new(@root, application, name) if regexp =~ name
        end
        res
      end

      #A dataservice.
      def data_service(name)
        DataService.new @root, @wrapped['data_services'][name], name
      end
      def data_services(regexp=nil)
        regexp||=/.*/
        res = Array.new
        @wrapped['data_services'].each_pair do |name,service|
          res << DataService.new(@root, service, name) if regexp =~ name
        end
        res
        
      end
      def to_json()
        @wrapped.to_json
      end
      
    end
    
    # Read/Write the JSON for a dataservice.
    # Does not map the actual JSON into a new ruby object.
    class DataService
      attr_accessor :wrapped, :role_name, :root
      def initialize(root, data, role_name)
        @root = root
        @wrapped = data
        @role_name = role_name
      end
      # returns the name of the service for cloudfoundry
      def name()
        @wrapped['name']
      end
      def vendor()
        @wrapped['vendor']
      end
      
      # Returns a vcap manifest that can be used
      # to create a new data-service to vcap's cloud_controller.
      def to_vcap_manifest()
        #TODO
        @wrapped
      end
      
    end
    
    # Read/Write the JSON for an application.
    # Does not map the actual JSON into a new ruby object.
    class Application
      attr_accessor :wrapped, :role_name, :root
      def initialize(root, data, role_name)
        @root = root
        @wrapped = data
        @role_name = role_name
      end
      # Returns the application name (different from the application role name.)
      def name()
        @wrapped['name']
      end
      def uris()
        @wrapped['uris']
      end
      def memory()
        @wrapped['resources']['memory']
      end
      def env()
        ApplicationEnvironment.new @wrapped['env'], self
      end
      
      # Returns a vcap manifest that can be used
      # to push/update an application to vcap's cloud_controller.
      def to_vcap_manifest()
        # This is pretty much identical to the json wrapped here except for the environment variables.
        # if there are differences we will take care of them here.
        @wrapped
      end
      
    end
    
    # Read/Write the application environment. a list of strings
    # where the first '=' character separate the key and values.
    class ApplicationEnvironment
      attr_accessor :wrapped, :application
      def initialize(data, application)
        @wrapped = data
        @application = application
      end
      #Sets a variable. Replaces other environment variables with the 
      #same name if there is such a thing.
      def set(name,value)
        foundit = false
        @wrapped.map! do |item|
          /^([\w]*)=(.*)$/ =~ item
          #puts "#{name} 1=#{$1} and 2=#{$2}"
          if ($1 == name)
            #puts "updating #{$1}"
            foundit = true
            "#{$1}=#{value}"
          else
            item
          end
        end
        #puts "appending #{name}=#{value}" unless foundit
        append(name,value) unless foundit
      end
      def get(name)
        @wrapped.each do |e|
          /^([\w]*)=(.*)$/ =~ e
          if ($1 == name)
            #puts "#{k}=name{v}"
            return $2
          end
        end
        return nil
      end
      def del(name)
        @wrapped.keep_if {|v| v =~ /^#{name}=/; $0.nil?}
      end
      def append(name,value)
        @wrapped << "#{name}=#{value}"
      end
    end
    
    class RecipesConfigurationApplier
      attr_accessor :root, :client, :applications, :recipes, :data_services, :opts
      # Select the applications and data-services to configure according to the values
      # in the SaaS manifest. When the selector is nil all of them are selected.
      def initialize(manifest, client, recipe_sel=nil, application_sel=nil, service_sel=nil, opts=nil)
        @root = Root.new manifest
        @client = client
        @opts=opts
        @recipes = @root.recipes(recipe_sel)
        @applications = Array.new
        @data_services = Array.new
        @recipes.each do |recipe|
          @applications = @applications + recipe.applications(application_sel)
          @data_services = @data_services + recipe.data_services(service_sel)
        end
        app_names = @applications.collect {|app| app.name } unless @opts && @opts[:data_only]
        service_names = @data_services.collect {|service| service.name } unless @opts && @opts[:apps_only]
        app_names ||= Array.new
        service_names ||= Array.new
        if app_names.empty? && service_names.empty?
          puts "No applications and data-services were selected."
        else
          puts "Applications selected #{app_names.join(', ')}" unless app_names.empty?
          puts "Data-services selected #{service_names.join(', ')}" unless service_names.empty?
        end
      end
      # Only for testing: inject json
      def __set_current(current_services=nil,current_services_info=nil)
        @current_services = current_services
        @current_services_info = current_services_info
      end
      def updates_pending()
        return @updates_report if @updates_report
        @current_services ||= @client.services
        @current_services_info ||= @client.services_info
        res = Hash.new
        data_services_updates = Hash.new
        applications_updates = Hash.new
        @data_service_updaters = Hash.new
        @application_updaters = Hash.new
        @data_services.each do |data_service|
           unless @data_service_updaters[data_service.name]
             data_service_updater = DataServiceManifestApplier.new data_service, @client, @current_services, @current_services_info
             @data_service_updaters[data_service.name] = data_service_updater
             updates = data_service_updater.updates_pending
             data_services_updates[data_service.name] = updates if updates
           end
        end
        @applications.each do |application|
           unless @application_updaters[application.name]
             application_updater = ApplicationManifestApplier.new application, @client
             @application_updaters[application.name] = application_updater
             updates = application_updater.updates_pending
             applications_updates[application.name] = updates if updates
             # if we did bind to a database; let's re-assign the ownership of the sql functions
             # to the favorite app if there is such a thing.
             if updates && updates['services'] && updates['services']['add']
               puts "THE ONE WE ARE DEBUGGING #{JSON.pretty_generate updates['services']}"
               list_services_name=updates['services']['add']
               list_services_name.each do |cf_service_name|
                 @data_services.each do |data_service|
                   if data_service.name == cf_service_name
                     # is this the privileged app?
                     priv_app_name = data_service.wrapped['director']['bound_app'] if data_service.wrapped['director']
                     if priv_app_name == application.name
                       puts "GOT THE PRIVILEGED APP #{application.name} for the service #{data_service.role_name}"
                       data_service.apply_privileges(priv_app_name)
                     end
                   end
                 end
               end
             end
           end
        end
        res['services'] = data_services_updates unless data_services_updates.empty?
        res['applications'] = applications_updates unless applications_updates.empty?
        @updates_report = res
        puts JSON.pretty_generate @updates_report
        @updates_report
      end
      def upload()
        @applications.each do |application|
          application_updater = ApplicationManifestApplier.new application, @client
          application_updater.upload
        end
      end
      def delete()
        @applications.each do |application|
          application_updater = ApplicationManifestApplier.new application, @client
          application_updater.delete
        end
        @data_services.each do |data_service|
          data_service_updater = DataServiceManifestApplier.new data_service, @client, @current_services, @current_services_info
          data_service_updater.delete
        end
      end
      def restart()
        stop()
        start()
      end
      def stop()
        @applications.each do |application|
          application_updater = ApplicationManifestApplier.new application, @client
          application_updater.stop
        end
      end
      def start()
        @applications.each do |application|
          application_updater = ApplicationManifestApplier.new application, @client
          application_updater.start
        end
      end
      def execute()
        return if updates_pending.empty?
        @data_service_updaters.each do |name,data_service_updater|
          data_service_updater.execute
        end
        @application_updaters.each do |name,application_updater|
          application_updater.execute
        end
      end
    end
    class DataServiceManifestApplier
      attr_accessor :data_service_json, :client, :current_services, :current_services_info
      def initialize(data_service,client,current_services=nil,current_services_info=nil)
        @client = client
        if data_service.kind_of? Hash
          @data_service_json = data_service
        elsif data_service.kind_of? DataService
          @data_service_json = data_service.wrapped
        else
          raise "Unexpected type of object to describe the data_service #{data_service}"
        end
        raise "Can't find the name of the data_service" if @data_service_json['name'].nil?
      end
      def current()
        return @current unless @current.nil?
        @current_services ||= @client.services
        @current_services_info ||= @client.services_info
        @current_services.each do |service|
          if service[:name] == @data_service_json['name']
            @current = service
            break
          end
        end
        @current ||= Hash.new # that would be a new service.
      end
      
      # Only for testing: inject json
      def __set_current(current,current_services=nil,current_services_info=nil)
        @current = current
        @current_services = current_services
        @current_services_info = current_services_info
      end
      def updates_pending()
        vendor = @data_service_json['vendor']
        name = @data_service_json['name']
        sh = service_hash()
        return "Create data-service #{name} vendor #{vendor}" if current().empty?
      end
      def execute()
        return unless updates_pending
        service_man = service_hash()
        puts "Calling client.create_service #{@data_service_json['vendor']}, #{@data_service_json['name']}"
        client.create_service @data_service_json['vendor'], @data_service_json['name']
      end
      def delete()
        raise "The service #{@data_service_json['name']} does not exist." if current().empty?
        client.delete_service(@data_service_json['name'])
      end

      # Returns the service manifest for the vendor.
      # If the service vendor ( = type) is not provided by this vcap install
      # An exception is raised.
      def service_hash()
        searched_vendor = @data_service_json['vendor']
        current()
        # in the vmc.rb code there is a comment that says 'FIXME!'
        @current_services_info.each do |service_type, value|
          value.each do |vendor, version|
            version.each do |version_str, service_descr|
              if searched_vendor == service_descr[:vendor]
                return {
                  "type" => service_descr[:type], "tier" => 'free',
                  "vendor" => searched_vendor, "version" => version_str
                }
              end
            end
          end
        end
        raise "vcap does not provide a data-service which vendor is #{searched_vendor}"
      end
      
      
    end    
    class ApplicationManifestApplier
      attr_accessor :application_json, :client, :current_name
      # @param application The application object as defined in the SaaS manifest
      # or the JSON for it.
      # @param client the vmc client object. assumed that it is logged in.
      def initialize(application, client, old_name=nil)
        @client = client
        if application.kind_of? Hash
          @application_json = application
        elsif application.kind_of? Application
          @application_json = application.wrapped
        else
          raise "Unexpected type of object to describe the application #{application}"
        end
        raise "Can't find the name of the application" if @application_json['name'].nil?
        @current_name = old_name
        @current_name ||= @application_json['old_name']
        @current_name ||= @application_json['name']
      end
      
      def safe_app_info(name)
        begin
          return @client.app_info(name)
        rescue VMC::Client::NotFound
          #expected
          return
        end
      end
      
      def current()
        return @current unless @current.nil?
        @current = safe_app_info(@current_name)
        @current ||= safe_app_info(@application_json['name']) # in case the rename occurred already.
        @current ||= Hash.new # that would be a new app.
      end
      
      # Only for testing: inject json
      def __set_current(current)
        @current = current
      end
      
      def execute()
        diff = updates_pending()
        if diff && diff.size > 0
          if @current['name'].nil? && @current[:name].nil?
            puts "Creating #{@application_json['name']} with #{updated_manifest.inspect}"
            @client.create_app(@application_json['name'], updated_manifest)
          elsif @current['name'] != @application_json['name']
            # This works for renaming the application too.
            puts "Updating #{@application_json['name']} with #{updated_manifest.inspect}"
            @client.update_app(@application_json['name'], updated_manifest)
          end
                    
        end
      end
      
      def upload()
        raise "The application #{@application_json['name']} does not exist yet" if current().empty?
        return unless @application_json['repository']
        url = @application_json['repository']['url']
        Dir.chdir(ENV['HOME']) do
          tmp_download_filename="_download_.zip"
          app_download_dir="vmc_knife_downloads/#{@application_json['name']}"
          `rm -rf #{app_download_dir}` if File.exist? "#{app_download_dir}/#{tmp_download_filename}"
          FileUtils.mkdir_p app_download_dir
          Dir.chdir(app_download_dir) do
            if Dir.entries(Dir.pwd).size == 2
              #empty directory.
              if /\.git$/ =~ url
                `git clone #{url} --depth 1`
                branch = @application_json['repository']['branch']
                if branch
                  `git checkout #{branch}`
                else
                  branch='master'
                end
                `git pull origin #{branch}`
              else
                begin
                  wget_args = @application_json['repository']['wget_args']
                  if wget_args.nil?
                    wget_args_str = ""
                  elsif wget_args.kind_of? Array
                    wget_args_str = wget_args.join(' ')
                  elsif wget_args.kind_of? String
                    wget_args_str = wget_args
                  end
                  `wget #{wget_args_str} --output-document=#{tmp_download_filename} #{url}`
                  raise "Unable to download #{url}" unless $? == 0
                  if /\.tgz$/ =~ url || /\.tar\.gz$/ =~ url
                    `tar zxvf #{tmp_download_filename}`
                  elsif /\.tar$/ =~ url
                    `tar xvf #{tmp_download_filename}`
                  else
                    `unzip #{tmp_download_filename}`
                  end
                ensure
                  `rm #{tmp_download_filename}`
                end
              end
            end
            Dir.chdir(@application_json['repository']['sub_dir']) if @application_json['repository']['sub_dir']
            `rm -rf .git` if File.exists? ".git"
            VMC::KNIFE::HELPER.static_upload_app_bits(@client,@application_json['name'],Dir.pwd)
          end
        end
      end
      
      def start()
        raise "The application #{@application_json['name']} does not exist yet" if current().empty?
        return if current[:state] == 'STARTED'
        current[:state] = 'STARTED'
        client.update_app(@application_json['name'], current())
      end
      
      def stop()
        raise "The application #{@application_json['name']} does not exist yet" if current().empty?
        return if current[:state] == 'STOPPED'
        current[:state] = 'STOPPED'
        client.update_app(@application_json['name'], current())
      end
      
      def delete()
        raise "The application #{@application_json['name']} does not exist yet" if current().empty?
        client.delete_app(@application_json['name'])
      end

      # Generate the updated application manifest:
      # take the manifest defined in the saas recipe
      # merge it with the current manifest of the application.
      def updated_manifest()
        new_app_manifest = JSON.parse(current.to_json) # a deep clone.
        #now let's update everything.
        new_mem = @application_json['resources']['memory'] unless @application_json['resources'].nil?
        new_app_manifest[:name] = @application_json['name']
        new_app_manifest['resources'] = Hash.new if new_app_manifest['resources'].nil?
        new_app_manifest['resources']['memory'] = new_mem unless new_mem.nil?
        unless @application_json['staging'].nil?
          new_app_manifest['staging'] = Hash.new if new_app_manifest['staging'].nil?
          new_app_manifest['staging']['model'] = @application_json['staging']['model'] unless @application_json['staging']['model'].nil?
          #new_app_manifest['staging']['framework'] = new_app_manifest['staging']['model']
          new_app_manifest['staging']['stack'] = @application_json['staging']['stack'] unless @application_json['staging']['stack'].nil?
        end
        new_app_manifest['uris'] = @application_json['uris'] unless @application_json['uris'].nil?
        new_app_manifest['services'] = @application_json['services'] unless @application_json['services'].nil?
        new_app_manifest['env'] = @application_json['env'] unless @application_json['env'].nil?
        if @application_json['meta']
          new_app_manifest['meta'] = Hash.new if new_app_manifest['meta'].nil?
          new_app_manifest['meta']['debug'] = @application_json['meta']['debug'] if @application_json['meta']['debug']
          new_app_manifest['meta']['restage_on_service_change'] = @application_json['meta']['restage_on_service_change'] if @application_json['meta']['restage_on_service_change']
        end
        new_app_manifest
      end
      
      # Returns a json object where we see the differences.
      def updates_pending()
        name = update_name_pending()
        services = update_services_pending()
        env = update_env_pending()
        memory = update_memory_pending()
        meta = meta_pending()
        uris = update_uris_pending()
        updates = Hash.new
        updates['name'] = name if name
        updates['services'] = services if services
        updates['env'] = env if env
        updates['uris'] = uris if uris
        updates['memory'] = memory if memory
        updates['meta'] = meta if meta
        updates unless updates.empty?
      end
      
      def update_name_pending()
        curr_name=current[:name] || current['name']
        if curr_name.nil?
          return "Create #{@application_json['name']}"
        end
        if @application_json['name'] != curr_name
          return "#{curr_name} => #{@application_json['name']}"
        end
      end
      def update_memory_pending()
        old_mem = current[:resources][:memory] if current[:resources]
        old_mem ||= current['resources']['memory'] if current['resources']
        new_mem = @application_json['resources']['memory'] unless @application_json['resources'].nil?
        if old_mem != new_mem
          return "#{old_mem} => #{new_mem}"
        end
      end
      def update_staging_pending()
        if current[:staging] # sym style: real vmc.
          old_model = current[:staging][:model]
          old_stack = current[:staging][:stack]
        elsif current['staging'] # string style: testing.
          old_model = current['staging']['model']
          old_stack = current['staging']['stack']
        end
        new_model = @application_json['staging']['model'] unless @application_json['staging'].nil?
        new_stack = @application_json['staging']['stack'] unless @application_json['staging'].nil?
        if old_model != new_model
          model_change "#{old_model} => #{new_model}"
        end
        if old_stack != new_stack
          stack_change "#{old_stack} => #{new_stack}"
        end
        return if model_change.nil? && stack_change.nil?
        return { "stack" => stack_change } if model_change.nil?
        return { "model" => model_change } if stack_change.nil?
        return { "stack" => stack_change, "model" => model_change }
      end
      def update_services_pending()
        old_services = current[:services] || current['services']
        new_services = @application_json['services']
        diff_lists(old_services,new_services)
      end
      def update_env_pending()
        old_services = current[:env] || current['env']
        new_services = @application_json['env']
        diff_lists(old_services,new_services)
      end
      def update_uris_pending()
        old_services = current[:uris] || current['uris']
        new_services = @application_json['uris']
        diff_lists(old_services,new_services)
      end
      # only look for debug and restage_on_service_change
      def meta_pending()
        old_meta = current[:meta] || current['meta'] || {}
        new_meta = @application_json['meta'] || {}
        old_debug = old_meta[:debug] || old_meta['debug']
        new_debug = new_meta['debug']
        debug_change = "#{old_debug} => #{new_debug}" if old_debug != new_debug
        
        old_restage_on_service_change = old_meta[:restage_on_service_change]
        old_restage_on_service_change = old_meta['restage_on_service_change'] unless old_restage_on_service_change == false
        old_restage_on_service_change = old_restage_on_service_change.to_s unless old_restage_on_service_change.nil?
        new_restage_on_service_change = new_meta['restage_on_service_change']
        restage_on_service_change_change = "#{old_restage_on_service_change} => #{new_restage_on_service_change}" if old_restage_on_service_change != new_restage_on_service_change
        
        return if debug_change.nil? && restage_on_service_change_change.nil?
        return { "debug" => debug_change } if restage_on_service_change_change.nil?
        return { "restage_on_service_change" => restage_on_service_change_change } if debug_change.nil?
        return { "debug" => debug_change, "restage_on_service_change" => restage_on_service_change_change }
      end
      def diff_lists(old_services,new_services)
        new_services ||= Array.new
        old_services ||= Array.new
        add = Array.new
        remove = Array.new
        new_services.each do |item|
          add << item unless old_services.include? item
        end
        old_services.each do |item|
          remove << item unless new_services.include? item
        end
        return if add.empty? && remove.empty?
        return { "add" => add } if remove.empty?
        return { "remove" => remove } if add.empty?
        return { "add" => add, "remove" => remove }
      end
    end
    
    # This is really a server-side vcap admin feature.
    class VCAPUpdateCloudControllerConfig
      def initialize(uri, cloud_controller_config=nil)
        @config = cloud_controller_config
        @config ||="#{ENV['HOME']}/cloudfoundry/config/cloud_controller.yml"
        @uri = uri
        raise "The config file #{@config} does not exist." unless File.exists? @config
      end
      def update_pending()
        res = false
        File.open(@config, "r") do |file|
          file.each_line do |s|
            if /^[\s]*external_uri:/ =~ s
              res = true unless /#{@uri}[\s]*$/ =~ s
            end
          end
        end
        return res
      end
      # look for
      #   cloud_controller_uri: http://api.intalio.me
      # and replace it with the new one.
      def update_gateway(config)
        changed = false
        lines = IO.readlines config
        File.open(config, "w") do |file|
          lines.each do |s|
            if /^[\s]*cloud_controller_uri:/ =~ s
              changed = true unless /#{@uri}[\s]*$/ =~ s
              file.puts "cloud_controller_uri: http://#{@uri}\n"
            else
              file.puts s
            end
          end
        end
        changed
      end
      def execute()
        @changed = false
        @changed_gateways = Array.new
        # look for the line that starts with external_uri: 
        # replace it with the new uri if indeed there was a change.
        lines = IO.readlines @config
        File.open(@config, "w") do |file|
          lines.each do |s|
            if /^[\s]*external_uri:/ =~ s
              @changed = true unless /#{@uri}[\s]*$/ =~ s
              file.puts "external_uri: #{@uri}\n"
            else
              file.puts s
            end
          end
        end
        if @changed
          #update the gateways too.
          @changed_gateways = Array.new
          yaml_files = Dir.glob File.join(File.dirname(@config), "*_gateway.yml")
          yaml_files.each do |path|
            if update_gateway(path)
              gateway = File.basename(path, '.yml')
              @changed_gateways << gateway
            end
          end
          cc_yml = File.open( @config ) { |yf| YAML::load( yf ) }
          pid = cc_yml['pid']
          if pid!=nil && File.exists?(pid)
            display "Restarting the reconfigured cloud_controller"
            #assuming that the vcap symlink is in place. maker sure the aliases
            # will be resolved.
            #`shopt -s expand_aliases; vcap restart cloud_controller`
            #TODO: something that looks nicer?
            system ". ~/.bashrc;\n vcap restart cloud_controller"
            @changed_gateways.each do |gateway|
              system ". ~/.bashrc;\n vcap restart #{gateway}"
            end
          end
        end
      end
      def was_changed()
        @changed
      end
    end
    
    # This is really a server-side feature.
    # Replace the 127.0.0.1 localhost #{old_uri} with the new uri
    class VCAPUpdateEtcHosts
      def initialize(uri, etc_hosts_path=nil,man=nil)
        @config = etc_hosts_path
        @config ||="/etc/hosts"
        @uri = uri
        raise "The config file #{@config} does not exist." unless File.exists? @config
      end
      def set_all_uris(uris_arr)
        uris_arr.push @uri unless @uri.nil?
        uris_arr.sort!
        uris_arr.uniq!
        @uri = uris_arr.join(' ')
      end
      def update_pending()
        #could also use:
        found_it=`sed -n '/^127\.0\.0\.1[[:space:]]*localhost[[:space:]]*#{@uri}/p' #{@config}`
        return true unless found_it && found_it.strip.length != 0
        return false
      end
      def execute()
        return unless update_pending
        @changed = false
        # look for the line that starts with external_uri: 
        # replace it with the new uri if indeed there was a change.
        if true
          # use sudo.
          puts "Executing sudo sed -i 's/^127\.0\.0\.1[[:space:]]*localhost.*$/127.0.0.1    localhost #{@uri}/g' #{@config}"
          `sudo sed -i 's/^127\.0\.0\.1[[:space:]]*localhost.*$/127.0.0.1    localhost #{@uri}/g' #{@config}`
        else
          lines = IO.readlines @config
          File.open(@config, "w") do |file|
            lines.each do |s|
              if /^127.0.0.1[\s]+localhost[\s]*/ =~ s
                @changed = true unless /^127.0.0.1[\s]+localhost[\s]+#{@uri}[\s]*/ =~ s
                file.puts "127.0.0.1\tlocalhost #{@uri}\n"
              else
                file.puts s
              end
            end
          end
        end
        #Edit the /etc/hostname file: (not a necessity so far).
        #`sudo hostname #{@uri}`
      end
      def was_changed()
        @changed
      end
    end
    
    # This is really a server-side feature.
    # This is deprecated; use the dns_publisher vcap module instead.
    # Regenerates the urls to publish as aliases.
    # use vmc apps to read the uris of each app and also the manifest.
    class VCAPUpdateAvahiAliases
      attr_accessor :do_exec, :uri_filter
      def initialize(avahi_aliases_path=nil, manifest_path=nil,client=nil,uri_filter=nil)
        @manifest_path = manifest_path
        @client = client
        @config = avahi_aliases_path
        @config ||= '/etc/avahi/aliases'
        @uri_filter = uri_filter||/\.local$/
      end
      def apps_uris()
        return @apps_uris unless @apps_uris.nil?
        uris = Array.new
        return uris unless @client
        apps = @client.apps
        api_uri = URI.parse(@client.target).host
        uris << api_uri if @uri_filter =~ api_uri
        apps.each do |app|
          app[:uris].each do |uri|
            #only publish the uris in the local domain.
            uris << uri if @uri_filter =~ uri
          end
        end
        uris.uniq!
        uris.sort!
        @apps_uris = uris
        @apps_uris
      end
      def manifest_uris()
        uris = Array.new
        return uris unless @manifest_path
        root = Root.new @manifest_path
        root.recipes.each do |recipe|
          recipe.applications.each do |application|
            application.uris.each do |uri|
              uris << uri if @uri_filter =~ uri
            end
          end
        end
        uris.uniq!
        uris.sort!
        uris
      end
      def all_uris()
        uris = manifest_uris+apps_uris
        uris.uniq!
        uris.sort!
        uris
      end
      def already_published_uris()
        already = IO.readlines @config
        already.collect! {|item| item.strip}
        already.select! {|item| !item.empty?}
        already.uniq!
        already.sort!
        already
      end
      def execute()
        return unless update_pending()
        # if the dns_publisher module is present let's not do this one.
        # the dns_publisher does a better job at mdns
        unless File.exist? "#{ENV['CLOUD_FOUNDRY_CONFIG_PATH']}/dns_publisher.yml"
          File.open(@config, "w") do |file|
            all_uris().each do |uri|
              file.puts uri + "\n"
            end
          end
          #configured so that we don't need root privileges on /etc/avahi/aliases:
          #the backticks don't work; system() works:
          system('avahi-publish-aliases') if @do_exec
        end
      end
      def update_pending()
        already = already_published_uris()
        length_already = already.length
        allall = already + all_uris()
        allall.uniq!
        return length_already != allall.length
      end
    end
    
  end # end of KNIFE
end
