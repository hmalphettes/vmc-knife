module VMCKNIFE
  ROOT_REL = File.expand_path(File.dirname(__FILE__))
end
require "#{VMCKNIFE::ROOT_REL}/restclient/restclient_add_timeout.rb"


module VMC
  module Cli
    module Command
      autoload :Knife,         "#{VMCKNIFE::ROOT_REL}/vmc_knife/commands/knife_cmds"
      autoload :Knifeapps,         "#{VMCKNIFE::ROOT_REL}/vmc_knife/commands/knife_cmds"
      autoload :Knifemisc,         "#{VMCKNIFE::ROOT_REL}/vmc_knife/commands/knife_cmds"
    end
  end
end


require "#{VMCKNIFE::ROOT_REL}/vmc_knife/json_expander"
require "#{VMCKNIFE::ROOT_REL}/vmc_knife/vmc_helper"
require "#{VMCKNIFE::ROOT_REL}/vmc_knife/vmc_knife"
require "#{VMCKNIFE::ROOT_REL}/vmc_knife/data_services"

require "#{VMCKNIFE::ROOT_REL}/vmc_knife/cli_extensions"
