require 'yaml'
require "interact"
require 'tempfile'

module VMC
  module KNIFE
    
    # returns only the result raw from psql
    PSQL_RAW_RES_ARGS="-P format=unaligned -P footer=off -P tuples_only=on"

    # Reads the cloud_controller config file for the connection parameters to ccdb.
    def self.get_ccdb_credentials(ccdb_yml_path="#{ENV['HOME']}/cloudfoundry/config/cloud_controller.yml", db_type='production')
      cc_conf = File.open( ccdb_yml_path ) do |yf| YAML::load( yf ) end
      db = cc_conf['database_environment'][db_type]
      db
    end
    
    def self.get_postgresql_node_credentials(postgresql_node_yml_path="#{ENV['HOME']}/cloudfoundry/config/postgresql_node.yml")
      db = File.open( postgresql_node_yml_path ) do |yf| YAML::load( yf ) end
      db['postgresql']
    end
        
    def self.get_app_id(app_name)
       db=get_ccdb_credentials()
       app_id = `psql --username #{db['username']} --dbname #{db['database']} -c \"select id from apps where name='#{app_name}'\" #{PSQL_RAW_RES_ARGS}`
       app_id
    end
    def self.get_service_config_id(service_name)
       db=get_ccdb_credentials()
       #todo add the user_id
       service_config_id = `psql --username #{db['username']} --dbname #{db['database']} -c \"select id from service_configs where alias='#{service_name}'\" #{PSQL_RAW_RES_ARGS}`
       service_config_id
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
    def self.get_credentials(service_name, app_name=nil)
       db=get_ccdb_credentials()
       puts "Credentials for #{service_name} with the user for the application #{app_name}"
       if app_name.nil?
         credentials_str = `psql --username #{db['username']} --dbname #{db['database']} -c \"select credentials from service_configs where alias='#{service_name}'\" #{PSQL_RAW_RES_ARGS}`
       else
         app_id = get_app_id(app_name)
         service_config_id = get_service_config_id(service_name)
         credentials_str = `psql --username #{db['username']} --dbname #{db['database']} -c \"select credentials from service_bindings where app_id = '#{app_id}' and service_config_id='#{service_config_id}'\" #{PSQL_RAW_RES_ARGS}`
       end
       res = Hash.new
       credentials_str.split("\n").each do | line |
         line =~ /([\w]*): ([\w|\.]*)$/
         res[$1] = $2 if $2
       end
       res
    end
    
    def self.pg_connect_cmd(credentials_hash, executable='psql',as_admin=false, other_params="")
      if executable =~ /vacuumlo$/
        # we don't have TEMP privilegeswhich are required by vacuumlo...
        #"export PGPASSWORD=#{credentials_hash['password']}; #{executable} -h #{credentials_hash['hostname']} -p #{credentials_hash['port']} -U #{credentials_hash['username']} #{credentials_hash['name']}"
        #workaround: use the superuser in the meantime:
        db=get_postgresql_node_credentials()
        db_arg = credentials_hash['name']
        return "export PGPASSWORD=#{db['pass']}; #{executable} -h #{db['host']} -p #{db['port']} -U #{db['user']} #{other_params} #{db_arg}"
      elsif executable =~ /pg_dump$/
        db_arg = "#{credentials_hash['name']}"
      else
        db_arg = "--dbname=#{credentials_hash['name']}"
      end
      if as_admin
        # usually as vcap/vcap
        db=get_postgresql_node_credentials()
        "export PGPASSWORD=#{db['pass']}; #{executable} --host=#{db['host']} --port=#{db['port']} --username=#{db['user']} #{other_params} #{db_arg}"
      else
        "export PGPASSWORD=#{credentials_hash['password']}; #{executable} --host=#{credentials_hash['hostname']} --port=#{credentials_hash['port']} --username=#{credentials_hash['username']} #{other_params} #{db_arg}"
      end
    end
    
    # command_files or command.
    def self.data_service_console(credentials_hash, commands_file="",as_admin=false)
      if credentials_hash['db'] #so far it has always been equal to 'db'
        # It is a mongo service
        #/home/ubuntu/cloudfoundry/.deployments/intalio_devbox/deploy/mongodb/bin/mongo 127.0.0.1:25003/db 
        #-u c417f26c-6f49-4dd5-a208-216107279c7a -p 8ab08355-6509-48d5-974f-27c853b842f5
        # Todo: compute the mongoshell path (?)
        mongo_shell=find_mongo_exec()
        cmd = "#{mongo_shell} -u #{credentials_hash['username']} -p #{credentials_hash['password']} #{credentials_hash['hostname']}:#{credentials_hash['port']}/#{credentials_hash['db']}"
        if commands_file
          if File.exists? commands_file
            # not supported yet.
            commands_file = "--eval \"#{`cat commands_file`}"
          else
            commands_file = "--eval \"#{commands_file}\""
          end
          `#{cmd} #{commands_file}`
        else
          # Replaces the current process.
          exec cmd
        end
      else
        cmd = pg_connect_cmd(credentials_hash, 'psql')
        if commands_file
          if File.exists? commands_file
            commands_file = "-f #{commands_file} #{PSQL_RAW_RES_ARGS}"
          else
            commands_file = "-c \"#{commands_file}\" #{PSQL_RAW_RES_ARGS}"
          end
          `#{cmd} #{commands_file}`
        else
          # Replaces the current process.
          exec cmd
        end
      end
    end
    
    def self.find_mongo_exec()
      mongo=`which mongo`
      return mongo unless mongo.nil? || mongo.size=0
      mongo_files = Dir.glob("#{ENV['HOME']}/cloudfoundry/.deployments", "*", "deploy/mongodb/bin/mongo")
      mongo_files.first unless mongo_files.empty?
    end
    
    def self.as_regexp(arg)
      if arg != nil && arg.kind_of?(String) && !arg.strip.empty?
        Regexp.new(arg)
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
        file_names = @opts[:file_names] if @opts
        app_name = @opts[:app_name] if @opts
        @data_services.each do |data_service|
          data_service.import(app_name,file_names)
        end
      end
      def export()
        file_names = opts()[:file_names] if opts()
        app_name = opts()[:app_name] if opts()
        @data_services.each do |data_service|
          data_service.export(app_name,file_names)
        end
      end
      def drop()
        collection_or_table_names = @opts[:collection_or_table_names] if @opts
        @data_services.each do |data_service|
          data_service.drop(collection_or_table_names)
        end
      end
      
    end
    
    class DataService
      include Interactive
      
      # The credentials hash for this data-service
      def credentials(app_name=nil)
        @credentials ||= VMC::KNIFE.get_credentials(name(), app_name)
        @credentials
      end
      
      # Connect to the mongo js shell or the psql shell.
      def shell(commands_file=nil,as_admin=false)
        VMC::KNIFE.data_service_console(credentials(),commands_file,as_admin)
      end
      
      def import(app_name,file)
        
      end
      
      def export(app_name=nil,file=nil)
        file = "#{name()}.sql"
        `touch #{file}`
        `chmod o+w #{file}`
        puts "Exports the database #{credentials(app_name)['name']} in #{file}"
        cmd = VMC::KNIFE.pg_connect_cmd(credentials(app_name), 'pg_dump', false, "--format=p --file=#{file} --no-owner --clean --oids --blobs --no-acl --no-privileges --no-tablespaces")
        puts cmd
        puts `#{cmd}`
        `chmod o-w #{file}`
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
          shell(cmd_acl,true)
        end
      end
      
      def drop(collection_or_table_names=nil)
        if is_postgresql
          sel_tables = "SELECT table_name FROM information_schema.tables WHERE table_schema='public'"
          if collection_or_table_names
            sel_tables = "#{sel_tables} AND table_name LIKE '#{collection_or_table_names}'"
          end
          tables = shell(sel_tables)
          tables_arr = Array.new
          tables.split("\n").each do | line |
            line.strip!
            tables_arr << line if line
          end
          if tables_arr.size > 0 && ask("Delete the tables \"#{tables_arr.join(',')}\"?", :default => true)
            #let's create a file in case there are a lot of tables:
            file = Tempfile.new('droptables')
            begin
              File.open(file.path, 'w') do |f2|
                tables_arr.each do |table|
                  f2.puts "DROP TABLE public.#{table} CASCADE;"
                end
              end
              puts shell(file.path)
            ensure
              file.unlink   # deletes the temp file
            end
          end
          puts "Vacuum orphaned large objects..."
          cmd = VMC::KNIFE.pg_connect_cmd(credentials(), 'vacuumlo')
          puts cmd
          puts `#{cmd}`
        elsif is_mongodb
          puts "TODO: Unsupported operation 'drop' for the data-service #{name()}"
        else
          puts "Unsupported operation 'drop' for the data-service #{name()}"
        end
      end
                                                                                                                                        
    end
    
  end
end
