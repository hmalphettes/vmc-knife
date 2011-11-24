require 'json'
module VMC
  module KNIFE
    module JSON_DIFF
    
    DIFF_NODE_NAME = "__diff__"
    TYPE_NODE_NAME = "__type__"
    PLUS="+"
    MINUS="-"
    CHANGED="=>"
    DISPLAY_TYPE_ONLY_WHEN_CHANGE=true
    
    def self.compare(a,b,pretty=true)
      if a.kind_of?(String) && b.kind_of?(String) && File.exists?(a) && File.exists?(b)
        a = JSON.parse File.open(a).read
        b = JSON.parse File.open(b).read
      end
      if pretty
        JSON.pretty_generate compare_tree(a, b)
      else
        compare_tree(a, b).to_json
      end
    end
    
    def self.compare_tree(a, b)
      typeA = a.class.name
      typeB = b.class.name
      
      aString = a.to_s unless is_array_or_hash?(a)
      bString = b.to_s unless is_array_or_hash?(b)
            
      node = Hash.new
      if a.nil?
        node[DIFF_NODE_NAME]=PLUS
        node[TYPE_NODE_NAME]=typeB unless DISPLAY_TYPE_ONLY_WHEN_CHANGE
        node['value']=bString if bString
      elsif b.nil?
        node[DIFF_NODE_NAME]=MINUS
        node[TYPE_NODE_NAME]=typeA unless DISPLAY_TYPE_ONLY_WHEN_CHANGE
        node['value']=aString if aString
      elsif (typeA != typeB) || (!aString.nil? && a != b)
        node[DIFF_NODE_NAME]=CHANGED
        if typeA != typeB
          node[TYPE_NODE_NAME]="#{typeA} => #{typeB}"
        else
          node[TYPE_NODE_NAME]=typeA unless DISPLAY_TYPE_ONLY_WHEN_CHANGE
        end
        node['value']="#{aString} => #{bString}" if aString
      else
        node[TYPE_NODE_NAME]=typeA unless DISPLAY_TYPE_ONLY_WHEN_CHANGE
        node['value']=aString if aString
      end
      
      if aString
        return node
      end
      child_node=node
#      child_node = Hash.new
#      node['child']=child_node
      keys = Array.new
      keys = collect_keys(a,keys)
      keys = collect_keys(b,keys)
      keys.sort!
      for i in 0..(keys.length-1)
        if (keys[i] != keys[i-1])
          value = compare_tree(a && a[keys[i]], b && b[keys[i]]);
          child_node[keys[i]]=value
        end
      end
      node
    end
    private
    def self.is_array_or_hash?(obj)
      obj.kind_of?(Array) || obj.kind_of?(Hash)
    end
    def self.collect_keys(obj, collector)
      return Array.new unless obj.kind_of? Hash
      collector + obj.keys
    end
    
    end # end of JSON_DIFF
  end # end of KNIFE
end
