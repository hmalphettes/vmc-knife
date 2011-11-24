require 'vmc/client'
require 'json'

module VMC
  module KNIFE
    module JSON_EXPANDER
    
      # Loads a json file.
      # Makes up to 10 passes evaluating ruby in the values that contain #{}.
      def self.expand_json(file_path)
        raise "The file #{file_path} does not exist" unless File.exists? file_path
        data = JSON.parse File.open(file_path).read
        #puts "got data #{data.to_json}"
        passes = 0
        while passes < 10
          break unless expand_data(data,data)
          passes += 1
        end
        raise "More than 10 passes evaluating the ruby template in the json file" unless passes < 10
        #puts "got data #{data.to_json}"
        data
      end
      
      # Traverses the JSON object
      # Eval the values that are strings and contain a #{}
      # Does not do it recursively
      # data The root data passed as 'this' in the binding to the eval function
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
