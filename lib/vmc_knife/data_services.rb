require 'yaml'

module VMC
  module KNIFE

    # Reads the cloud_controller config file for the connection parameters to ccdb.
    def self.get_ccdb_credentials(ccdb_yml_path="#{ENV['HOME']}/cloudfoundry/config/cloud_controller.yml", db_type='production')
      cc_conf = File.open( ccdb_yml_path ) do |yf| YAML::load( yf ) end
      db = cc_conf['database_environment'][db_type]
      db
    end
    
    # Returns a hash of the credentials for a data-service
    # For example for postgres:
    #--- 
    #name: dc82ca85dfef740b7841211f354068beb
    #host: 192.168.1.6
    #hostname: 192.168.1.6
    #port: 5432
    #user: uafe612fbe7714af0ab04db22e199680d
    #username: uafe612fbe7714af0ab04db22e199680d
    #password: pd829916bfac34b3185e0f1158bf8920b
    #node_id: postgresql_node_0  
    #
    # For example for mongo:
    #hostname: 192.168.0.103                       +
    #host: 192.168.0.103                           +
    #port: 25003                                   +
    #name: 266401da-6853-4657-b212-814bd6f9d844    +
    #db: db                                        +
    #username: c417f26c-6f49-4dd5-a208-216107279c7a+
    #password: 8ab08355-6509-48d5-974f-27c853b842f5+
    #node_id: mongodb_node_0
    #
    def self.get_credentials(service_name)
#       credentials_str = `sudo -u postgres psql --dbname #{ccdb_name} -c \"select credentials from service_configs where alias='#{service_name}'\" -P format=unaligned -P footer=off -P tuples_only=on`
       db=get_ccdb_credentials()
       credentials_str = `psql --username #{db['username']} --dbname #{db['database']} -c \"select credentials from service_configs where alias='#{service_name}'\" -P format=unaligned -P footer=off -P tuples_only=on`
       res = Hash.new
       credentials_str.split("\n").each do | line |
         line =~ /([\w]*): ([\w|\.]*)$/
         res[$1] = $2 if $2
       end
       res
    end
    
    # command_files or command.
    def self.data_service_console(credentials_hash, commands_file="")
      if credentials_hash['db'] #so far it has always been equal to 'db'
        # It is a mongo service
        #/home/ubuntu/cloudfoundry/.deployments/intalio_devbox/deploy/mongodb/bin/mongo 127.0.0.1:25003/db 
        #-u c417f26c-6f49-4dd5-a208-216107279c7a -p 8ab08355-6509-48d5-974f-27c853b842f5
        # Todo: compute the mongoshell path (?)
        mongo_shell="mongo"
        `#{mongo} -u #{credentials_hash['username']} -p #{credentials_hash['password']} #{credentials_hash['hostname']}:#{credentials_hash['port']}/#{credentials_hash['db']} #{commands_file}`
      else
        cmd = "export PGPASSWORD=#{credentials_hash['password']}; psql --host=#{credentials_hash['hostname']} --port=#{credentials_hash['port']} --username=#{credentials_hash['username']} --dbname=#{credentials_hash['name']}"
        if commands_file
          if File.exists? commands_file
            commands_file = "-f #{commands_file}"
          else
            commands_file = "-c \"#{commands_file}\""
          end
          `#{cmd} #{commands_file}`
        else
          # Replaces the current process.
          exec cmd
        end
      end
    end
    
    class RecipesConfigurationApplier
      
      def shell()
        @data_services.each do |data_service|
          data_service.shell
        end
      end
      def credentials()
        @data_services.each do |data_service|
          data_service.credentials
        end
      end
      def apply_privileges()
        @data_services.each do |data_service|
          data_service.apply_privileges
        end
      end
      def import()
        @data_services.each do |data_service|
          data_service.import
        end
      end
      def export()
        @data_services.each do |data_service|
          data_service.export
        end
      end
      def drop()
        @data_services.each do |data_service|
          data_service.drop
        end
      end
      
    end
    
    class DataService
                                                                                                                                                                        
      # The credentials hash for this data-service
      def credentials()
        @credentials ||= VMC::KNIFE.get_credentials(name())
        @credentials
      end
      
      # Connect to the mongo js shell or the psql shell.
      def shell(commands_file=nil)
        VMC::KNIFE.data_service_console(credentials(),commands_file)
      end
      
      def import(file)
                                                                                                                                                   
      end
      
      def export(file)
        
      end
      
      def is_postgresql()
        credentials()['db'] == nil
      end
                                                                                                                                                      
      def is_mongodb()
        credentials()['db'] != nil
      end
                                                                                                                                                      
      def apply_privileges()
        if is_postgresql()
          cmd_acl="GRANT CREATE ON SCHEMA PUBLIC TO PUBLIC;\
          GRANT ALL ON ALL TABLES IN SCHEMA PUBLIC TO PUBLIC;\
          GRANT ALL ON ALL FUNCTIONS IN SCHEMA PUBLIC TO PUBLIC;\
          GRANT ALL ON ALL SEQUENCES IN SCHEMA PUBLIC TO PUBLIC;"
          console(cmd_acl)
        end
      end
      
      def drop(collection_or_table_names=/.*/)
        if collection_or_table_names.kind_of? String
          collection_or_table_names = Regexp.new collection_or_table_names
        end
      end
                                                                                                                                        
    end
    
  end
end
