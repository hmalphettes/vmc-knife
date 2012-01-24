require 'vmc/client'
require 'json'

module VMC
  module KNIFE
    module JSON_EXPANDER
      
      # Reads the ip of a given interface and the mask
      # defaults on eth0 then on wlan0 and then whatever it can find that is not 127.0.0.1
      def self.ip_auto(interface='eth0')
        ifconfig = File.exist? "/sbin/ifconfig" ? "/sbin/ifconfig" : "ifconfig"
        res=`#{ifconfig} | sed -n '/#{interface}/{n;p;}' | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}' | head -1`
        if interface == 'eth0' && (res.nil? || res.strip.empty?)
          res = ip_auto "wlan0"
          res = res[0] if res
          if res.strip.empty?
            #nevermind fetch the first IP you can find that is not 127.0.0.1
            res=`#{ifconfig} | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}' | head -1`
          end
        end
        res.strip! if res
        unless res.empty?
          # gets the Mask
          line=`#{ifconfig} | grep 'inet addr:#{res}' | awk '{ print $1}' | head -1`
#          puts "parsing ip and mask in line #{line}"
          mask=`#{ifconfig} | grep 'inet addr:#{res}' | grep -v '127.0.0.1' | cut -d: -f4 | awk '{ print $1}' | head -1`
          mask.strip!
#          puts "got ip #{res} and mask #{mask}"
          return [ res, mask ]
        end
      end
      
      # Derive a seed guaranteed unique on the local network  according to the IP.
      def self.ip_seed()
        ip_mask=ip_auto()
        ip = ip_mask[0]
        mask = ip_mask[1]
        ip_segs = ip.split('.')
        if mask.start_with? "255.255.255."
          ip_segs[3]
        elsif mask.start_with? "255.255"
          "#{ip_segs[2]}-#{ip_segs[3]}"
        elsif mask.start_with? "255."
          "#{ip_segs[1]}-#{ip_segs[2]}-#{ip_segs[3]}"
        else
          #hum why are we here?
          "#{ip_segs[0]}-#{ip_segs[1]}-#{ip_segs[2]}-#{ip_segs[3]}"
        end
      end
    
      # Loads a json file.
      # Makes up to 10 passes evaluating ruby in the values that contain #{}.
      def self.expand_json(file_path)
        raise "The file #{file_path} does not exist" unless File.exists? file_path
        data = File.open(file_path, "r") do |infile| JSON.parse infile.read end
        #puts "got data #{data.to_json}"
        passes = 0
        while passes < 150
          #puts "pass #{passes}"
          break unless expand_data(data,data)
          passes += 1
        end
        puts data.to_json unless passes < 150
        raise "More than 100 passes evaluating the ruby template in the json file current state #{JSON.pretty_generate data}" unless passes < 100
        #puts "got data #{data.to_json}"
        
        data
      end
      
      # Traverses the JSON object
      # Eval the values that are strings and contain a #{}
      # Does not do it recursively
      # data The root data passed as 'this' in the binding to the eval function
      # @return true if there was a change.
      def self.expand_data(data,current)
        at_least_one_eval = false
        if current.kind_of? Hash
          current.each_pair do | k, v |
            if v.kind_of? String
              if /\#{.+}/ =~ v
                at_least_one_eval = true
                begin
                  evalled = eval_v(v,data,current)
                  current[k] = evalled unless evalled.nil?
                rescue => e
                  raise "Error thrown evaluating #{v}: #{e.inspect}"
                end
              end
            else
              at_least_one_eval ||= expand_data(data,v)
            end
          end
        elsif current.kind_of? Array
          index = 0
          current_evalled = Array.new
          do_flatten=false
          current.each do | v |
            if v.kind_of? String
              if /\#{.+}/ =~ v
                at_least_one_eval = true
                begin
                  evalled_ret = eval_v(v,data,current)
                  if evalled_ret.kind_of? Array
                    # we choose to support our use cases to flatten the arrays.
                    # never mind the lists of list for now.
                    do_flatten = true
                    evalled_ret.each do |nitem|
                      current_evalled[index] = nitem
                      index+=1
                    end
                  elsif evalled_ret.nil? # skip the nil for the next pass
                    current_evalled[index] = v
                  else
                    current_evalled[index] = evalled_ret
                  end
                rescue => e
                  raise "Error thrown evaluating #{v}; current state #{JSON.pretty_generate data}: #{e.inspect}"
                end
              else
                current_evalled[index] = v
              end
#            else
#              at_least_one_eval ||= expand_data(data,v)
            end
            index+=1
          end
          
          # we don't support list of lists if there is a doubt when running the eval.
          if at_least_one_eval
            current_evalled.flatten! if do_flatten
            current.clear
            current.concat current_evalled
          end
          
          current.each do | v |
            unless v.kind_of? String
              at_least_one_eval ||= expand_data(data,v)
            end
          end
          
        end
        at_least_one_eval
      end
      
      # internal eval a reference.
      # the reference is always wrapped in a json string.
      # however if it is purely a ruby script ("#{ruby here}" ) we unwrap it
      def self.eval_v(v,data,current,recurse=0)
        if /^\#{([^}]*)}$/ =~ v
          val = $1
        else
          val = '"'+v+'"'
        end
          module_eval <<-"END"
  def self.eval_block_from_template(this,current)
    #{val}
  end
END
        evalled = eval_block_from_template(data,current)
        return nil if evalled.nil?
        if evalled.kind_of?(String) && /\#{([^}]*)}/ =~ evalled
          if recurse < 20
            evalled = eval_v(evalled,data,current,recurse+1)
          else
            return nil
          end
        end
        evalled
      end
      
      def self.get_binding(this,current)
        binding
      end
      
    end #end of JSON_EXPANDER
    
  end # end of KNIFE
  
end
