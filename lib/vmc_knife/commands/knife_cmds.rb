# Commands for vmc_knife.

module VMC::KNIFE::Cli
  
  #loads the manifest file.
  #when the path is not specified, look in the current directory.
  #when the path is a directory, look for the first json file it can find.
  #if it still find nothing then use the default which is the value of the environment variable VMC_KNIFE_DEFAULT_RECIPE
  #the json file actually loaded is set as the attribute @manifest_path
  def load_manifest(manifest_file_path=nil)
    was_nil = true if manifest_file_path.nil?
    manifest_file_path = Dir.pwd if manifest_file_path.nil?
    if File.directory? manifest_file_path
      #look for the first .json file if possible that is not an expanded.json
      Dir.glob(File.join(manifest_file_path,"*.json")).each do |file|
        @manifest_path = file
        if VMC::Cli::Config.trace
          display "Using the manifest #{@manifest_path}"
        end
        return VMC::KNIFE::JSON_EXPANDER.expand_json @manifest_path
      end
      if was_nil && !ENV['VMC_KNIFE_DEFAULT_RECIPE'].nil?
        raise "Can't load the default recipe VMC_KNIFE_DEFAULT_RECIPE=#{ENV['VMC_KNIFE_DEFAULT_RECIPE']}" unless File.exists? ENV['VMC_KNIFE_DEFAULT_RECIPE']
        load_manifest ENV['VMC_KNIFE_DEFAULT_RECIPE']
      else
        raise "Unable to find a *.json file in #{manifest_file_path}"
      end
    else
      @manifest_path = manifest_file_path
      return VMC::KNIFE::JSON_EXPANDER.expand_json @manifest_path
    end
  end
end

module VMC::Cli::Command

  class Knife < Base
    include VMC::KNIFE::Cli
    
    # expands the json manifest. outputs it in the destination path.
    
    def expand_manifest(manifest_file_path=ENV['VMC_KNIFE_DEFAULT_RECIPE'], destination=nil)
      res = VMC::KNIFE::JSON_EXPANDER.expand_json manifest_file_path
      if destination
        display "Expanding the manifest #{manifest_file_path} into #{destination}"
        if VMC::Cli::Config.trace
          display JSON.pretty_generate(res)
        end
        File.open(destination, 'w') {|f| f.write(JSON.pretty_generate(res)) }
      else
        STDERR.puts "Expanding the manifest #{manifest_file_path}"
        STDOUT.puts JSON.pretty_generate(res) 
      end
      
    end
    
    # updates the cloud_controller
    def configure_cloud_controller(cloud_controller_yml=nil,manifest_file_path_or_uri=nil)
      __update(manifest_file_path_or_uri,cloud_controller_yml,VMC::KNIFE::VCAPUpdateCloudControllerConfig,"cloud_controller")
    end
    # updates /etc/hosts
    def configure_etc_hosts(etc_hosts=nil,manifest_file_path=nil,client=nil)
      #__update(manifest_file_path_or_uri,etc_hosts,VMC::KNIFE::VCAPUpdateEtcHosts,"/etc/hosts")
      
      # this will configure /etc/hosts with the urls of your applications as well as the cloudcontroller.
      # it is not be necessary if avahi is correctly configured on your VM.
      unless manifest_file_path.nil?
        if File.exists? manifest_file_path
          man = load_manifest(manifest_file_path)
          uri = man['target']
        else
          uri = manifest_file_path
        end
      else
        man = load_manifest(nil)
        uri = man['target']
      end
      # if there is a port remove it.
      uri = uri.split(':')[0] if uri
      update_aliases = VMC::KNIFE::VCAPUpdateAvahiAliases.new(nil,man,client,/.*/)
      update_hosts = VMC::KNIFE::VCAPUpdateEtcHosts.new(uri,manifest_file_path,client)
      update_hosts.set_all_uris(update_aliases.all_uris)
      if update_hosts.update_pending()
        display "Configuring /etc/hosts with uri: #{uri}" if VMC::Cli::Config.trace
        update_hosts.execute()
      end
    end
    # updates /etc/avahi/aliases
    def configure_etc_avahi_aliases(etc_avahi_aliases=nil,manifest_file_path=nil)
      man = load_manifest(manifest_file_path)
      update_aliases = VMC::KNIFE::VCAPUpdateAvahiAliases.new(etc_avahi_aliases,man,client)
      update_aliases.do_exec = true
      update_aliases.execute
    end
    
    def configure_all(manifest_file_path_or_uri=nil)
      begin
        display "Stop applications ..."
        VMC::Cli::Command::Knifeapps.new(@options).stop_applications(nil,manifest_file_path_or_uri)
      rescue
        #nevermind. sometimes a wrong config we can't login and we can't stop the apps.
      end
      display "Configure_cloud_controller ..."
      change = configure_cloud_controller(nil,manifest_file_path_or_uri)
      display "Configure_etc_hosts ..."
      configure_etc_hosts(nil,manifest_file_path_or_uri)
      display "Login again ..."
      new_knife = VMC::Cli::Command::Knifemisc.new(@options)
      new_knife.login(manifest_file_path_or_uri)
      # set the new client object to the old command.
      @client = new_knife.client
      display "Configure_applications ..."
      VMC::Cli::Command::Knifeapps.new(@options).configure_applications(nil,manifest_file_path_or_uri)
      display "Configure_etc_avahi_aliases ..."
      configure_etc_avahi_aliases(nil,manifest_file_path_or_uri)
      display "Start applications ..."
      VMC::Cli::Command::Knifeapps.new(@options).restart_applications(nil,manifest_file_path_or_uri)
    end

    private
    def __update(manifest_file_path_or_uri,config,_class,msg_label)
      unless manifest_file_path_or_uri.nil?
        if File.exists? manifest_file_path_or_uri
          man = load_manifest(manifest_file_path_or_uri)
          uri = man['target']
        else
          uri = manifest_file_path_or_uri
        end
      else
        man = load_manifest(nil)
        uri = man['target']
      end
      raise "No uri defined" unless uri
      # if there is a port remove it.
      uri = uri.split(':')[0]
      update_cc = _class.new(uri,config)
      if update_cc.update_pending()
        display "Configuring #{msg_label} with uri: #{uri}" if VMC::Cli::Config.trace
        update_cc.execute()
        true
      else
        false
      end
    end

  end
  
  class Knifemisc < Misc
    include VMC::KNIFE::Cli
    
    # configures the target and login according to the info in the manifest.
    def login(manifest_file_path=nil)
      man  = load_manifest(manifest_file_path)
      target_url = man['target']
      raise "No target defined in the manifest #{@manifest_path}" if target_url.nil? 
      puts "set_target #{target_url}"
      set_target(target_url)
      
      email = man['email']
      password = man['password']
      @options[:email] = email if email
      @options[:password] = password if password
      
      tries ||= 0
      # login_and_save_token:
      
      puts "login with #{email} #{password}"
      token = client.login(email, password)
      VMC::Cli::Config.store_token(token)
      
    rescue VMC::Client::TargetError
      display "Problem with login, invalid account or password.".red
      retry if (tries += 1) < 3 && prompt_ok && !@options[:password]
      exit 1
    rescue => e
      display "Problem with login, #{e}, try again or register for an account.".red
      display e.backtrace
      exit 1
      
    end
    
  end
  
  class Knifeapps < Apps
    include VMC::KNIFE::Cli

    def configure_applications(app_names_regexp=nil,manifest_file_path=nil)
      configure(nil,nil,app_names_regexp,manifest_file_path,
                        {:apps_only=>true})
    end
    def configure_services(services_names_regexp=nil,manifest_file_path=nil)
      configure(nil,nil,services_names_regexp,manifest_file_path,
                        {:data_only=>true})
    end
    def configure_recipes(recipe_names_regexp=nil,manifest_file_path=nil)
      configure(recipe_names_regexp,nil,nil,manifest_file_path)
    end
              
    # Configure the applications according to their manifest.
    # The parameters are related to selecting a subset of the applications to configure.
    # nil means all apps for all recipes found in the manifest are configured.
    # @param recipes The list of recipes: nil: search the apps in all recipes
    # @param app_role_names The names of the apps in each recipe; nil: configure all apps found.
    def configure(recipes_regexp=nil,app_names_regexp=nil,service_names_regexp=nil,manifest_file_path=nil,opts=nil)
      man = load_manifest(manifest_file_path)
      recipes_regexp = as_regexp(recipes_regexp)
      app_names_regexp = as_regexp(app_names_regexp)
      service_names_regexp = as_regexp(service_names_regexp)
      configurer = VMC::KNIFE::RecipesConfigurationApplier.new(man,client,recipes_regexp,app_names_regexp,service_names_regexp,opts)
      if VMC::Cli::Config.trace
        display "Pending updates"
        display JSON.pretty_generate(configurer.updates_pending)
      end
      configurer.execute
    end
    def upload_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:upload,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true, :force=>@options[:force]})
    end
    def update_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:update,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true, :force=>@options[:force]})
    end
    def start_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:start,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true})
    end
    def stop_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:stop,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true})
    end
    def restart_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:restart,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true})
    end
    def info_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:info,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true})
    end
    def delete_all(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:delete,nil,app_names_regexp,nil,manifest_file_path)
    end
    def delete_apps(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:delete,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true})
    end
    def delete_data(services_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:delete,nil,nil,services_names_regexp,manifest_file_path,
                        {:data_only=>true})
    end
    def data_shell(data_names_regexp=nil,file_or_cmd=nil,app_name=nil,manifest_file_path=nil)
      file_name = nil
      cmd = nil
      if file_or_cmd
        if File.exist? file_or_cmd
          file_name = file_or_cmd
        else
          cmd = file_or_cmd
          cmd = cmd[1..-1] if cmd.start_with?('"') || cmd.start_with?("'")
        end
      end
      recipe_configuror(:shell,nil,nil,data_names_regexp,manifest_file_path,
                        {:file_name=>file_name, :data_cmd=>cmd, :app_name=>app_name, :data_only=>true})
    end
    def data_credentials(data_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:credentials,nil,nil,data_names_regexp,manifest_file_path,
                        {:data_only=>true})
    end
    def data_apply_privileges(data_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:apply_privileges,nil,nil,data_names_regexp,manifest_file_path,
                        {:data_only=>true})
    end
    def data_import(data_names_regexp=nil,file_names=nil,app_name=nil,manifest_file_path=nil)
      recipe_configuror(:import,nil,nil,data_names_regexp,manifest_file_path,
                        {:file_names=>file_names, :app_name=>app_name, :data_only=>true})
    end
    def data_export(data_names_regexp=nil,file_names=nil,app_name=nil,manifest_file_path=nil)
      recipe_configuror(:export,nil,nil,data_names_regexp,manifest_file_path,
                        {:file_names=>file_names, :app_name=>app_name, :data_only=>true})
    end
    def data_drop(data_names_regexp=nil,collection_or_table_names=nil,manifest_file_path=nil)
      recipe_configuror(:drop,nil,nil,data_names_regexp,manifest_file_path,
                        {:collection_or_table_names=>collection_or_table_names, :data_only=>true})
    end
    def data_shrink(data_names_regexp=nil,collection_or_table_names=nil,manifest_file_path=nil)
      recipe_configuror(:shrink,nil,nil,data_names_regexp,manifest_file_path,
                        {:collection_or_table_names=>collection_or_table_names, :data_only=>true})
    end
    def logs_all(app_names_regexp=nil, output_file=nil, manifest_file_path=nil)
      recipe_configuror(:logs,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true, :output_file=>output_file, :log_apps=>true, :log_vcap=>true})
    end
    def logs_apps(app_names_regexp=nil, manifest_file_path=nil)
      recipe_configuror(:logs,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true, :log_apps=>true, :log_vcap=>false})
    end
    def logs_vcap(app_names_regexp=nil, manifest_file_path=nil)
      recipe_configuror(:logs,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true, :log_apps=>false, :log_vcap=>true})
    end
    def logs_less(app_names_regexp=nil, log_files_glob=nil, manifest_file_path=nil)
      recipe_configuror(:logs_shell,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true, :log_apps=>true, :log_vcap=>false, :logs_shell=>"less",
                         :log_files_glob=>log_files_glob})
    end
    def logs_tail(app_names_regexp=nil, log_files_glob=nil, manifest_file_path=nil)
      recipe_configuror(:logs_shell,nil,app_names_regexp,nil,manifest_file_path,
                        {:apps_only=>true, :log_apps=>true, :log_vcap=>false, :logs_shell=>"tail",
                         :log_files_glob=>log_files_glob})
    end
    
    def recipe_configuror(method_sym_name,recipes_regexp=nil,app_names_regexp=nil,service_names_regexp=nil,manifest_file_path=nil,opts=nil)
      man = load_manifest(manifest_file_path)
      recipes_regexp = as_regexp(recipes_regexp)
      app_names_regexp = as_regexp(app_names_regexp)
      service_names_regexp = as_regexp(service_names_regexp)
      configurer = VMC::KNIFE::RecipesConfigurationApplier.new(man,client,recipes_regexp,app_names_regexp,service_names_regexp,opts)
      method_object = configurer.method(method_sym_name)
      method_object.call
    end
    
    def as_regexp(arg)
      if arg != nil && arg.kind_of?(String) && !arg.strip.empty?
        Regexp.new(arg)
      end
    end
    
  end
  
end