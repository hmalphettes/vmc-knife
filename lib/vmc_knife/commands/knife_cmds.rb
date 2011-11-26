# Commands for vmc_knife.

module VMC::KNIFE::Cli
  
  #loads the manifest file.
  #when the path is not specified, look in the current directory.
  #when the path is a directory, look for the first json file it can find.
  #the json file actually loaded is set as the attribute @manifest_path
  def load_manifest(manifest_file_path=nil)
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
      raise "Unable to find a *.json file in #{manifest_file_path}"
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
    def expand_manifest(manifest_file_path, destination=nil)
      res = VMC::KNIFE::JSON_EXPANDER.expand_json manifest_file_path
      if destination.nil?
        noextension = File.basename(manifest_file_path, File.extname(manifest_file_path))
        destination = File.join File.dirname(manifest_file_path), "#{noextension}.expanded.json"
      end
      display "Expanding the manifest #{manifest_file_path} into #{destination}"
      if VMC::Cli::Config.trace
        display JSON.pretty_generate(res)
      end
      File.open(destination, 'w') {|f| f.write(JSON.pretty_generate(res)) }
    end
    
    # updates the cloud_controller
    def configure_cloud_controller(cloud_controller_yml=nil,manifest_file_path_or_uri=nil)
      __update(manifest_file_path_or_uri,cloud_controller_yml,VMC::KNIFE::VCAPUpdateCloudControllerConfig,"cloud_controller")
    end
    # updates /etc/hosts
    def configure_etc_hosts(etc_hosts=nil,manifest_file_path_or_uri=nil)
      __update(manifest_file_path_or_uri,etc_hosts,VMC::KNIFE::VCAPUpdateEtcHosts,"/etc/hosts")
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
      configure(nil,nil,app_names_regexp,manifest_file_path)
    end
    def configure_services(services_names_regexp=nil,manifest_file_path=nil)
      configure(nil,nil,services_names_regexp,manifest_file_path)
    end
    def configure_recipes(recipe_names_regexp=nil,manifest_file_path=nil)
      configure(recipe_names_regexp,nil,nil,manifest_file_path)
    end
              
    # Configure the applications according to their manifest.
    # The parameters are related to selecting a subset of the applications to configure.
    # nil means all apps for all recipes found in the manifest are configured.
    # @param recipes The list of recipes: nil: search the apps in all recipes
    # @param app_role_names The names of the apps in each recipe; nil: configure all apps found.
    def configure(recipes_regexp=nil,app_names_regexp=nil,service_names_regexp=nil,manifest_file_path=nil)
      man = load_manifest(manifest_file_path)
      configurer = VMC::KNIFE::RecipesConfigurationApplier.new(man,client,recipes_regexp,app_names_regexp,service_names_regexp)
      if VMC::Cli::Config.trace
        display "Pending updates"
        display JSON.pretty_generate(configurer.updates_pending)
      end
      configurer.execute
    end
    
    def upload_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:upload,nil,nil,app_names_regexp,manifest_file_path)
    end
    def start_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:start,nil,nil,app_names_regexp,manifest_file_path)
    end
    def stop_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:stop,nil,nil,app_names_regexp,manifest_file_path)
    end
    def restart_applications(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:restart,nil,nil,app_names_regexp,manifest_file_path)
    end
    def delete_all(app_names_regexp=nil,manifest_file_path=nil)
      recipe_configuror(:delete,nil,nil,app_names_regexp,manifest_file_path)
    end
    
    def recipe_configuror(method_sym_name,recipes_regexp=nil,app_names_regexp=nil,service_names_regexp=nil,manifest_file_path=nil)
      man = load_manifest(manifest_file_path)
      configurer = VMC::KNIFE::RecipesConfigurationApplier.new(man,client,recipes_regexp,app_names_regexp,service_names_regexp)
      method_object = configurer.method(method_sym_name)
      method_object.call
    end
    
  end
  
end