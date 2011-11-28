require 'vmc/client'
require 'json'

module VMC
  module KNIFE
    module JSON_EXPANDER
      
      # Reads the ip of a given interface and the mask
      # defaults on eth0 then on wlan0 and then whatever it can find that is not 127.0.0.1
      def self.ip_auto(interface='eth0')
        res=`ifconfig | sed -n '/#{interface}/{n;p;}' | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}' | head -1`
        if interface == 'eth0' && (res.nil? || res.strip.empty?)
          res = VcapUtilities.ip_auto "wlan0"
          if res.strip.empty?
            #nevermind fetch the first IP you can find that is not 127.0.0.1
            res=`ifconfig | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}' | head -1`
          end
        end
        res.strip! if res
        unless res.empty?
          # gets the Mask
          line=`ifconfig | grep 'inet addr:#{res}' | awk '{ print $1}' | head -1`
          puts "parsing ip and mask in line #{line}"
          mask=`ifconfig | grep 'inet addr:#{res}' | grep -v '127.0.0.1' | cut -d: -f4 | awk '{ print $1}' | head -1`
          mask.strip!
          puts "got ip #{res} and mask #{mask}"
          return [ res, mask ]
        end
      end
    
      # Derive a seed guaranteed unique on the local network  according to the IP.
      def self.ip_seed()
        ip_mask=ip_auto()
        ip = ip_mask[0]
        mask = ip_mask[1]
        ip_segs = ip.split('.')
        if mask == "255.255.255.0"
          ip_segs[3]
        elsif mask == "255.255.0.0"
          "#{ip_segs[2]}-#{ip_segs[3]}"
        elsif mask == "255.0.0.0"
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
        data = JSON.parse File.open(file_path).read
        #puts "got data #{data.to_json}"
        passes = 0
        while passes < 100
          #puts "pass #{passes}"
          break unless expand_data(data,data)
          passes += 1
        end
        puts data.to_json unless passes < 100
        raise "More than 100 passes evaluating the ruby template in the json file" unless passes < 100
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
          current.each do | v |
            if v.kind_of? String
              if /\#{.+}/ =~ v
                at_least_one_eval = true
                begin
                  evalled = eval_v(v,data,current)
                  current[index] = evalled unless evalled.nil?
                rescue => e
                  raise "Error thrown evaluating #{v}: #{e.inspect}"
                end
              end
            else
              at_least_one_eval ||= expand_data(data,v)
            end
            index+=1
          end
        end
        at_least_one_eval
      end
      
      # internal eval a reference.
      # the reference is always wrapped in a json string.
      # however if it is purely a ruby script ("#{ruby here}" ) we unwrap it
      # to avoid casting the result into a string.
      def self.eval_v(v,data,current)
        #puts "evalling #{v}"
        if /^\#{([^}]*)}$/ =~ v
          val = $1
        else
          val = '"'+v+'"'
        end
        evalled = eval(val,get_binding(data,current))
        #puts "evaluating #{v} => #{evalled} class #{evalled.class.name}"
        evalled
      end
      
      def self.get_binding(this,current)
        binding
      end
      
    end #end of JSON_EXPANDER
    
  end # end of KNIFE
  
end
