require 'yaml'
require "interact"
require 'tempfile'
require 'tmpdir'
require 'pathname'
require 'erb'

module VMC
  module KNIFE
    
    # returns only the result raw from psql
    PSQL_RAW_RES_ARGS="-P format=unaligned -P footer=off -P tuples_only=on"

    # Reads the cloud_controller config file for the connection parameters to ccdb.
    def self.get_ccdb_credentials(ccdb_yml_path="#{ENV['CLOUD_FOUNDRY_CONFIG_PATH']}/cloud_controller.yml", db_type='production')
      cc_conf = File.open( ccdb_yml_path ) do |yf| YAML::load( yf ) end
      db = cc_conf['database_environment'][db_type]
      db
    end
    
    def self.get_postgresql_node_credentials(postgresql_node_yml_path="#{ENV['CLOUD_FOUNDRY_CONFIG_PATH']}/postgresql_node.yml")
      db = File.open( postgresql_node_yml_path ) do |yf| YAML::load( yf ) end
      db['postgresql']
    end
    
    def self.get_mongodb_node_config(mongodb_node_yml_path="#{ENV['CLOUD_FOUNDRY_CONFIG_PATH']}/mongodb_node.yml")
      db = File.open( mongodb_node_yml_path ) do |yf| YAML::load( yf ) end
      db
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
       if app_name.nil?
         credentials_str = `psql --username #{db['username']} --dbname #{db['database']} -c \"select credentials from service_configs where alias='#{service_name}'\" #{PSQL_RAW_RES_ARGS}`
       else
         app_id = get_app_id(app_name)
         service_config_id = get_service_config_id(service_name)
         credentials_str = `psql --username #{db['username']} --dbname #{db['database']} -c \"select credentials from service_bindings where app_id = '#{app_id}' and service_config_id='#{service_config_id}'\" #{PSQL_RAW_RES_ARGS}`
       end
       res = Hash.new
       credentials_str.split("\n").each do | line |
         line =~ /([\w]*): ([\w|\.|-]*)$/
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
        db_arg = "#{other_params} #{credentials_hash['name']}"
      else
        #the other params are at the end
        db_arg = "--dbname=#{credentials_hash['name']} #{other_params}"
      end
      if as_admin
        # usually as vcap/vcap
        db=get_postgresql_node_credentials()
        "export PGPASSWORD=#{db['pass']}; #{executable} --host=#{db['host']} --port=#{db['port']} --username=#{db['user']} #{db_arg}"
      else
        "export PGPASSWORD=#{credentials_hash['password']}; #{executable} --host=#{credentials_hash['hostname']} --port=#{credentials_hash['port']} --username=#{credentials_hash['username']} #{db_arg}"
      end
    end
    
    # command_files or command.
    def self.data_service_console(credentials_hash, commands_file="",as_admin=false,exec_name=nil,return_value=false)
      if credentials_hash['db'] #so far it has always been equal to 'db'
        # It is a mongo service
        #/home/ubuntu/cloudfoundry/.deployments/intalio_devbox/deploy/mongodb/bin/mongo 127.0.0.1:25003/db 
        #-u c417f26c-6f49-4dd5-a208-216107279c7a -p 8ab08355-6509-48d5-974f-27c853b842f5
        # Todo: compute the mongoshell path (?)
        exec_name ||= 'mongo'
        mongo_shell=get_mongo_exec(exec_name)
        if exec_name == 'mongo'
          db_arg = "/#{credentials_hash['db']}"
        elsif exec_name == 'mongodump'
          db_arg = "" # dump all the databases including 'admin' which contains the users.
        else
          db_arg = "--db #{credentials_hash['db']}"
        end
        cmd = "#{mongo_shell} -u #{credentials_hash['username']} -p #{credentials_hash['password']} #{credentials_hash['hostname']}:#{credentials_hash['port']}#{db_arg}"
        if commands_file
          if mongo_shell == 'mongo'
            if File.exists? commands_file
              # not supported yet.
              commands_file = "--eval \"#{`cat commands_file`}"
            else
              commands_file = "--eval \"#{commands_file}\""
            end
          end
          the_cmd = "#{cmd} #{commands_file}"
          puts "#{the_cmd}" if VMC::Cli::Config.trace
          puts `#{the_cmd}`
        else
          puts "#{cmd}" if VMC::Cli::Config.trace
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
          the_cmd = "#{cmd} #{commands_file}"
          puts "#{the_cmd}" if VMC::Cli::Config.trace
          return `#{the_cmd}` if return_value
          puts `#{the_cmd}`
        else
          puts "#{cmd}" if VMC::Cli::Config.trace
          # Replaces the current process.
          exec cmd
        end
      end
    end
    
    def self.get_mongo_exec(exec_name=nil)
      exec_name||='mongo'
      mongo_bin_folder=File.dirname(get_mongodb_node_config()['mongod_path'])
      File.join(mongo_bin_folder,exec_name)
    end
    
    # Returns the path to the mongodb db files. /var/vcap/services/mongodb/
    def self.get_mongodb_base_dir(mongodb_node_yml_path=nil)
      mongodb_node_yml_path||="#{ENV['CLOUD_FOUNDRY_CONFIG_PATH']}/mongodb_node.yml"
      db = File.open( mongodb_node_yml_path ) do |yf| YAML::load( yf ) end
      base_dir = db['base_dir']
    end
    
    def self.as_regexp(arg)
      if arg != nil && arg.kind_of?(String) && !arg.strip.empty?
        Regexp.new(arg)
      elsif arg.kind_of?(Regexp)
        arg
      end
    end
    
    class RecipesConfigurationApplier
      def shell()
        app_name = @opts[:app_name] if @opts
        file_name = @opts[:file_name] if @opts
        data_cmd = @opts[:data_cmd] if @opts
        if data_cmd
          file_name = data_cmd
        end
        @data_services.each do |data_service|
          data_service.shell(file_name)
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
        file_names = @opts[:file_names] if @opts
        app_name = @opts[:app_name] if @opts
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
      def shrink()
        collection_or_table_names = @opts[:collection_or_table_names] if @opts
        @data_services.each do |data_service|
          data_service.shrink(collection_or_table_names)
        end
      end
      
    end
    
    class DataService
      include Interactive
      
      # The credentials hash for this data-service
      def credentials(app_name=nil)
        #bound_app is the name of an app bound to the dat-service and that credentials
        #should be used to access the data-service.
        #for example if an app creates large objects you will need to use
        #the credentials of that app to find the objects.
        app_name ||= @wrapped['director']['bound_app'] if @wrapped['director']
        @credentials ||= VMC::KNIFE.get_credentials(name(), app_name)
        @credentials
      end
      
      # Connect to the mongo js shell or the psql shell.
      def shell(commands_file=nil,as_admin=false,return_value=false)
        VMC::KNIFE.data_service_console(credentials(),commands_file,as_admin,nil,return_value)
      end
      
      def import(app_name=nil,file=nil)
        file ||= @wrapped['director']['import_url'] if @wrapped['director']
        if file.nil?
          files = Dir.glob("#{name()}.*")
          raise "Unable to locate the database file to import." if files.empty?
          file = files.first
        end
        

        tmp_download_filename="_download_.zip"
        data_download_dir="#{ENV['HOME']}/vmc_knife_downloads/data_#{@wrapped['name']}"
        current_wd=Dir.pwd
        FileUtils.mkdir_p data_download_dir
        Dir.chdir(data_download_dir) do
          if file =~ /^https?:\/\// || file =~ /^ftp:\/\//
            basename = Pathname.new(URI.parse(file).path).basename.to_s
          else
            file=File.expand_path(file,current_wd)
            basename = File.basename(file).to_s
          end
          if Dir.entries(Dir.pwd).size == 2
            if file =~ /^https?:\/\// || file =~ /^ftp:\/\//
              wget_args = @wrapped['director']['wget_args']
              if wget_args.nil?
                wget_args_str = ""
              elsif wget_args.kind_of? Array
                wget_args_str = wget_args.join(' ')
              elsif wget_args.kind_of? String
                wget_args_str = wget_args
              end
              `wget #{wget_args_str} --output-document=#{basename} #{file}`
              if $? != 0
                `rm #{data_download_dir}/#{basename}`
                raise "Unable to successfully download #{file}"
              end
            else
              `cp #{file} #{basename}`
            end
          end
          #unzip if necessary (in progress)
          is_unzipped=true
          p "unzip #{basename}"
          if /\.tgz$/ =~ basename || /\.tar\.gz$/ =~ basename
            `tar zxvf #{basename}`
          elsif /\.tar$/ =~ basename
            `tar xvf #{basename}`
          elsif /\.zip$/ =~ basename
            `unzip #{basename}`
          else
            is_unzipped=false
          end
          
          if is_unzipped
            #`rm #{basename}`
            files = Dir.glob("*.sql") if is_postgresql
            files = Dir.glob("*.bson") if is_mongodb
            files ||= Dir.glob("*")
            raise "Can't find the db-dump file." if files.empty?
            file = files.first
          else
            file = basename
          end
          
          if is_postgresql
            p "chmod o+w #{file}"
            `chmod o+w #{file}`
            creds=credentials(app_name)
            if /\.sql$/ =~ file
              other_params="--file #{file} --quiet"
              cmd = VMC::KNIFE.pg_connect_cmd(creds, 'psql',as_admin=false, other_params)
              #`psql --dbname #{dbname} --file #{file} --clean --quiet --username #{rolename}`
            else
              other_params="--clean --no-acl --no-privileges --no-owner #{file}"
              cmd = VMC::KNIFE.pg_connect_cmd(creds, 'pg_restore',false, other_params)
              #`pg_restore --dbname=#{dbname} --username=#{username} --no-acl --no-privileges --no-owner #{file}`
            end
            puts cmd
            puts `#{cmd}`
            `chmod o-w #{file}`
          elsif is_mongodb
            
            # see if we go through the filesystem to shrink or
            # if we are only interested in the data itself.
            base_dir=VMC::KNIFE.get_mongodb_base_dir()
            instance_name=creds['name']
            dbpath=File.join(base_dir, instance_name, 'data')            
            mongod_lock=File.join(dbpath,'mongod.lock')
            
            if File.exists?(mongod_lock) && File.size(mongod_lock)>0
              # the mongodb instance is currently working. connect to it and do the work.
              # in that case import the 'db' alone. don't do the 'admin'
              VMC::KNIFE.data_service_console(creds, File.dirname(file),false,'mongorestore')
            else
              # the mongodb instance is not currently working
              # go directly on the filesystem
              `rm -rf #{dbpath}`
              `mkdir -p #{dbpath}`
              #sudo mongorestore --dbpath /var/lib/mongodb
              mongorestore_exec=VMC::KNIFE.get_mongo_exec('mongorestore')
              `#{mongorestore_exec} --dbpath #{dbpath} #{File.dirname(File.dirname(file))}`
            end
          else
            raise "Unsupported type of data-service. Postgresql and mongodb are the only supported services at the moment."
          end
        end
      end
      
      def export(app_name=nil,file=nil)
        if is_postgresql
          if file.nil?
            extension = @wrapped['director']['file_extension'] if @wrapped['director']
            extension ||= "sql"
            file = "#{name()}.#{extension}"
          else
            unless File.exists?(File.dirname(file))
              raise "The output folder #{File.dirname(file)} does not exist."
            end
          end
          archive_unzipped=file
          archive_unzipped="#{name()}.sql" unless /\.sql$/ =~ extension
          `touch #{archive_unzipped}`
          unless File.exists? archive_unzipped
            raise "Unable to create the file #{archive_unzipped}"
          end
          `chmod o+w #{archive_unzipped}`
          puts "Exports the database #{credentials(app_name)['name']} in #{file}"
          #sudo -u postgres env PGPASSWORD=intalio DBNAME=intalio DUMPFILE=intalio_dump.sql pg_dump --format=p --file=$DUMPFILE --no-owner --clean --blobs --no-acl --oid --no-tablespaces $DBNAME
          #sudo -u postgres env PGPASSWORD=$PGPASSWORD DUMPFILE=$DUMPFILE pg_dump --format=p --file=$DUMPFILE --no-owner --clean --blobs --no-acl --oid --no-tablespaces $DBNAME

          cmd = VMC::KNIFE.pg_connect_cmd(credentials(app_name), 'pg_dump', false, "--format=p --file=#{archive_unzipped} --no-owner --clean --oids --blobs --no-acl --no-privileges --no-tablespaces")
          puts cmd
          puts `#{cmd}`
          
          unless File.exists? archive_unzipped
            raise "Unable to read the file #{archive_unzipped}"
          end
          `chmod o-w #{archive_unzipped}`
        elsif is_mongodb
          if file.nil?
            extension = @wrapped['director']['file_extension'] if @wrapped['director']
            extension ||= "bson.tar.gz"
            file = "#{name()}.#{extension}"
          end
          creds=credentials(app_name)
          puts "Exports the database #{creds['name']} in #{file}"
          #mongodump --host localhost:27017
          mongodump_exec=VMC::KNIFE.get_mongo_exec('mongodump')
          # see if we go through the filesystem or through the network:
          base_dir=VMC::KNIFE.get_mongodb_base_dir()
          instance_name=creds['name']
          dbpath=File.join(base_dir, instance_name, 'data')            
          mongod_lock=File.join(dbpath,'mongod.lock')
          puts "looking at #{mongod_lock} exists? #{File.exists?(mongod_lock)} size #{File.size(mongod_lock)}"
          if File.exists?(mongod_lock) && File.size(mongod_lock)>0
            cmd = "#{mongodump_exec} -u #{creds['username']} -p #{creds['password']} --host #{creds['hostname']}:#{creds['port']} --db db"
          else
            cmd = "#{mongodump_exec} --dbpath #{dbpath}"
          end
          puts cmd
          puts `#{cmd}`
          archive_unzipped="dump"
        end
          
        
        # this produces a dump folder in the working directory.
        # let's zip it:
        if /\.zip$/ =~ file
          # just zip
          `zip -r #{file} #{archive_unzipped}`
        elsif /\.tar$/ =~ file
          # just tar
          `tar -cvf #{file} #{archive_unzipped}`
        else
          # tar-gzip by default
          `tar -czvf #{file} #{archive_unzipped}`
        end
        `rm -rf #{archive_unzipped}` if archive_unzipped != file
      end
      
      def is_postgresql()
        credentials()['db'] == nil
      end
                                                                                                                                                      
      def is_mongodb()
        credentials()['db'] != nil
      end
      
      # Make sure that all users who can connect to the DB can also access
      # the tables.
      # This workarounds the privilege issue reported .... and was added to "my"
      # branch of vcap's services 
      # 
      # Another workaround though really not perfect so it will stay in vmc_knife:
      # the ownership of the SQL functions.
      def apply_privileges(app_name=nil)
        if is_postgresql()
          cmd_acl="GRANT CREATE ON SCHEMA PUBLIC TO PUBLIC;\
          GRANT ALL ON ALL TABLES IN SCHEMA PUBLIC TO PUBLIC;\
          GRANT ALL ON ALL FUNCTIONS IN SCHEMA PUBLIC TO PUBLIC;\
          GRANT ALL ON ALL SEQUENCES IN SCHEMA PUBLIC TO PUBLIC;\
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO PUBLIC;\
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO PUBLIC;\
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO PUBLIC;"
#          shell(cmd_acl,true)
          
          # reset the owner of the functions to the current user
          # when there is a 'privileged' app.
          app_name ||= @wrapped['director']['bound_app'] if @wrapped['director']
          if app_name
            cmd_select_fcts="SELECT pg_proc.proname FROM pg_catalog.pg_proc WHERE \
     pg_proc.pronamespace=(SELECT pg_namespace.oid FROM pg_catalog.pg_namespace WHERE pg_namespace.nspname = 'public') \
 AND pg_proc.proowner!=(SELECT oid FROM pg_roles WHERE rolname = 'postgres')"
            current_owner=credentials()['username']
            unless current_owner
              STDERR.puts "The application #{app_name} is not bound to the data-service #{name}; not applying the database privileges."
              return
            end
            fcts_name=shell(cmd_select_fcts,true,true)
            fcts = fcts_name.split("\n").collect do |line|
              line.strip!
              "'#{line}'"
            end.join(',')
            cmd_change_fcts_owner="UPDATE pg_catalog.pg_proc \
                SET proowner = (SELECT oid FROM pg_roles WHERE rolname = '#{current_owner}')\
                WHERE pg_proc.proname IN (#{fcts})"
            puts `sudo -u postgres psql --dbname #{credentials()['name']} -c \"#{cmd_change_fcts_owner}\" #{PSQL_RAW_RES_ARGS}`
          end
        end
      end
      
      # shrink the size of the databses on the file system.
      # Specifically act on the mongodb instances when they are stopped.
      def shrink(collection_or_table_names=nil)
        return unless is_mongodb
        creds=credentials()
        base_dir=VMC::KNIFE.get_mongodb_base_dir()
        instance_name=creds['name']
        dbpath=File.join(base_dir, instance_name, 'data')            
        mongod_lock=File.join(dbpath,'mongod.lock')
        raise "Can't shrink #{name}; the mongodb is currently running" if File.exists?(mongod_lock) && File.size(mongod_lock)>0
        mongodump_exec=VMC::KNIFE.get_mongo_exec('mongodump')
        raise "Can't find mongodump" unless File.exist? mongodump_exec
        mongorestore_exec=VMC::KNIFE.get_mongo_exec('mongorestore')
        raise "Can't find mongorestore" unless File.exist? mongorestore_exec
        cmd = "#{mongodump_exec} --dbpath #{dbpath}"
        puts "#{cmd}"
        puts `#{cmd}`
        
        `rm -rf #{dbpath}`
        `mkdir #{dbpath}`
        cmd = "#{mongorestore_exec} --dbpath #{dbpath} dump/"
        puts "#{cmd}"
        puts `#{cmd}`
        `rm -rf dump`
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
          # generate the command file from the erb template.
          filter = ".*"
          filterIsNegated = "false";
          skipSystem = "true";
          if collection_or_table_names
            if collection_or_table_names.start_with?('!')
              filterIsNegated = "true";
              filter = collection_or_table_names[1..-1]
            else
              filter = collection_or_table_names
            end
          end
          # this command is applied to each collection.
          # the name of the variable is 'collection' as can bee seen in the erb file.
          cmd="collection.drop();"
          
          file = Tempfile.new('dropcollections')
          begin
            File.open(file.path, 'w') do |f2|
              template = ERB.new File.new("#{VMCKNIFE::ROOT_REL}/vmc_knife/mongo/mongo_cmd.js.erb").read, nil, "%"
              f2.puts template.result(binding)
            end
            puts shell(file.path)
          ensure
            file.unlink   # deletes the temp file
          end
          
          #TODO: iterate over the collections and drop them according to the filter.
          #raise "TODO: Unsupported operation 'drop' for the data-service #{name()}"
        else
          puts "Unsupported operation 'drop' for the data-service #{name()}"
        end
      end

    end
    
  end
end
