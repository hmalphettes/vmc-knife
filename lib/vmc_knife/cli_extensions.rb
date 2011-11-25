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
      if @args.size == 1
        set_cmd(:knife, :expand_manifest, 1)
      elsif @args.size == 2
        set_cmd(:knife, :expand_manifest, 2)
      else
        set_cmd(:knife, :expand_manifest)
      end
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
    when 'configure-applications'
      usage('vmc_knife configure-applications [<applications_regexp>]')
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
    when 'help'
      display "vmc_knife expand-manifest|login|diff|update|configure-all|configure-recipes|configure-applications|configure-services|configure-vcap|configure-vcap-mdns|configure-vcap-etc-hosts [<manifest_path>]"
    else
      super
    end
  end
  
end
