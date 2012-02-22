require 'rubygems'
require 'cli' #this is the cli from vmc.

# Adds some new commands to the vmc's cli.
#
# Reconfigure applications according to a saas recipe.
# The SaaS recipe is a json object that contains the manifest of each application.
# as well as a short declaration of the services expected and their nature.
# Usage: edit the json recipe.
# vmc_knife configure-applications
# 
# Also bundles utilities to reconfigure the hostname of the cloud_controller and the gateways accordingly:
# vmc_knife configure-vcap
# and publish the urls in the deployed apps with zeroconf on ubuntu (avahi)
# vmc configure-vcap-mdns
class VMC::Cli::KnifeRunner < VMC::Cli::Runner
  
  def parse_command!
    # just return if already set, happends with -v, -h
    return if @namespace && @action
    
    verb = @args.first
    case verb

    when 'expand-manifest'
      usage('vmc_knife expand-manifest <path_to_json_manifest> <path_to_destination_expanded_manifest>')
      @args.shift # consumes the argument.
      set_cmd(:knife, :expand_manifest, @args.size)
    when 'login', 'target'
      usage('vmc_knife login [<path_to_json_manifest>]')
      @args.shift # consumes the argument.
      if @args.size == 1
        set_cmd(:knifemisc, :login, 1)
      else
        set_cmd(:knifemisc, :login)
      end
    when 'configure-all'
      usage('vmc_knife configure-all [<path_to_cloud_controller_config_yml>] [<path_to_json_manifest_or_uri>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knife, :configure_all, @args.size)
      else
        set_cmd(:knife, :configure_all, @args.size) # too many
      end
    when 'configure-vcap'
      usage('vmc_knife configure-vcap [<path_to_cloud_controller_config_yml>] [<path_to_json_manifest_or_uri>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knife, :configure_cloud_controller, @args.size)
      else
        set_cmd(:knife, :configure_cloud_controller, @args.size) # too many
      end
    when 'configure-vcap-etc-hosts'
      usage('vmc_knife configure-vap-etc-hosts [<path_to_etc_hosts>] [<path_to_json_manifest_or_uri>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knife, :configure_etc_hosts, @args.size)
      else
        set_cmd(:knife, :configure_etc_hosts, @args.size) # too many
      end
    when 'configure-vcap-mdns'
      usage('vmc_knife configure-vap-mdns [<path_to_aliases>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knife, :configure_etc_avahi_aliases, @args.size)
      else
        set_cmd(:knife, :configure_etc_avahi_aliases, @args.size) # too many
      end
    when 'configure-applications','configure-apps'
      usage('vmc_knife configure-apps [<applications_regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :configure_applications, @args.size)
      else
        set_cmd(:knifeapps, :configure_applications, @args.size) # too many
      end
    when 'configure-services'
      usage('vmc_knife configure-services [<services_regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :configure_services, @args.size)
      else
        set_cmd(:knifeapps, :configure_services, @args.size) # too many
      end
    when 'configure-recipes'
      usage('vmc_knife configure-recipes [<recipes_regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :configure_recipes, @args.size)
      else
        set_cmd(:knifeapps, :configure_recipes, @args.size) # too many
      end
    when 'upload-applications','upload-apps'
      usage('vmc_knife upload-apps [<applications_regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :upload_applications, @args.size)
      else
        set_cmd(:knifeapps, :upload_applications, @args.size) # too many
      end
    when 'start-applications','start-apps'
      usage('vmc_knife start-apps [<applications_regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :start_applications, @args.size)
      else
        set_cmd(:knifeapps, :start_applications, @args.size) # too many
      end
    when 'stop-applications','stop-apps'
      usage('vmc_knife stop-apps [<applications_regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :stop_applications, @args.size)
      else
        set_cmd(:knifeapps, :stop_applications, @args.size) # too many
      end
    when 'restart-applications','restart-apps'
      usage('vmc_knife restart-apps [<applications_regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :restart_applications, @args.size)
      else
        set_cmd(:knifeapps, :restart_applications, @args.size) # too many
      end
    when 'delete-all'
      usage('vmc_knife delete-all [<applications_regexp>]')
      @args.shift # consumes the argument.
      set_cmd(:knifeapps, :delete_all, @args.size)
    when 'delete-apps'
      usage('vmc_knife delete-apps [<applications_regexp>]')
      @args.shift # consumes the argument.
      set_cmd(:knifeapps, :delete_apps, @args.size)
    when 'delete-data','delete-services'
      usage('vmc_knife delete-data [<data_regexp>]')
      @args.shift # consumes the argument.
      set_cmd(:knifeapps, :delete_data, @args.size)
    when 'data-shell','psql','mongo'
      usage('vmc_knife data-shell [<data-service-name>] [<app-name>] [<cmd-file> or <quoted-cmd>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :data_shell, @args.size)
      else
        set_cmd(:knifeapps, :data_shell, @args.size) # too many
      end
    when 'data-apply-privileges'
      usage('vmc_knife data-apply-privileges [<data-service-name>] [<app-name>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :data_apply_privileges, @args.size)
      else
        set_cmd(:knifeapps, :data_apply_privileges, @args.size) # too many
      end
    when 'data-credentials'
      usage('vmc_knife data-credentials [<data-service-name>] [<app-name>]')
      @args.shift # consumes the argument.
      if @args.size <= 2
        set_cmd(:knifeapps, :data_credentials, @args.size)
      else
        set_cmd(:knifeapps, :data_credentials, @args.size) # too many
      end
    when 'data-drop'
      usage('vmc_knife data-drop [<data-service-name>] [<tables-collection-regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 3
        set_cmd(:knifeapps, :data_drop, @args.size)
      else
        set_cmd(:knifeapps, :data_drop, @args.size) # too many
      end
    when 'data-shrink'
      usage('vmc_knife data-shrink [<data-service-name>] [<tables-collection-regexp>]')
      @args.shift # consumes the argument.
      if @args.size <= 3
        set_cmd(:knifeapps, :data_shrink, @args.size)
      else
        set_cmd(:knifeapps, :data_shrink, @args.size) # too many
      end
    when 'data-import'
      usage('vmc_knife data-import [<data-service-name>] [<archive-file-name>] [<tables-collection-regexp>]')
      @args.shift # consumes the argument.
      set_cmd(:knifeapps, :data_import, @args.size)
    when 'data-export'
      usage('vmc_knife data-export [<data-service-name>] [<archive-file-name>] [<tables-collection-regexp>]')
      @args.shift # consumes the argument.
      set_cmd(:knifeapps, :data_export, @args.size)
    when 'logs','logs-all'
      usage('vmc_knife logs-all')
      @args.shift # consumes the argument.
      if @args.size <= 3
        set_cmd(:knifeapps, :logs_all, @args.size)
      else
        set_cmd(:knifeapps, :logs_all, @args.size) # too many
      end
    when 'logs-apps'
      usage('vmc_knife logs-apps')
      @args.shift # consumes the argument.
      if @args.size <= 3
        set_cmd(:knifeapps, :logs_apps, @args.size)
      else
        set_cmd(:knifeapps, :logs_apps, @args.size) # too many
      end
    when 'logs-vcap'
      usage('vmc_knife logs-vcap')
      @args.shift # consumes the argument.
      if @args.size <= 3
        set_cmd(:knifeapps, :logs_vcap, @args.size)
      else
        set_cmd(:knifeapps, :logs_vcap, @args.size) # too many
      end
    when 'less','logs-less','logs-shell'
      usage('vmc_knife less <application name>')
      @args.shift # consumes the argument.
      set_cmd(:knifeapps, :logs_less, @args.size)
    when 'tail','logs-tail'
      usage('vmc_knife tail <application name>')
      @args.shift # consumes the argument.
      set_cmd(:knifeapps, :logs_tail, @args.size)
    when 'update-self'
      usage('vmc_knife update-self')
      puts "Updating vmc-knife"
      `cd /tmp; [ -d "vmc-knife" ] && rm -rf vmc-knife; git clone https://github.com/hmalphettes/vmc-knife.git; cd vmc-knife; gem build vmc_knife.gemspec; gem install vmc_knife`
      exit 0
    when 'help'
      display "vmc_knife expand-manifest|login|start/stop/restart-apps|upload-apps|configure-all|configure-recipes|configure-apps|configure-services|delete-app/data/all|configure-vcap|configure-vcap-mdns|configure-vcap-etc-hosts|data-shell|data-export/import/shrink/drop|logs-less|less|tail|logs-all/apps/vcap|update-self [<manifest_path>]"
    else
      super
    end
  end
  
end
