module VMCKNIFE; end

ROOT_REL = File.expand_path(File.dirname(__FILE__))
require "#{ROOT_REL}/restclient/restclient_add_timeout.rb"


module VMC
  module Cli
    module Command
      autoload :Knife,         "#{ROOT_REL}/vmc_knife/commands/knife_cmds"
      autoload :Knifeapps,         "#{ROOT_REL}/vmc_knife/commands/knife_cmds"
      autoload :Knifemisc,         "#{ROOT_REL}/vmc_knife/commands/knife_cmds"
    end
  end
end


require "#{ROOT_REL}/vmc_knife/json_expander"
require "#{ROOT_REL}/vmc_knife/vmc_helper"
require "#{ROOT_REL}/vmc_knife/vmc_knife"
require "#{ROOT_REL}/vmc_knife/data_services"

require "#{ROOT_REL}/vmc_knife/cli_extensions"
