require 'rest_client'

# Make sure the rest-client won't time out too quickly:
# vmc uses the rest-client for its rest calls but does not let us configure the timeouts.
# We monkey patch here.
module RestClient

  class << self
    attr_accessor :timeout
    attr_accessor :open_timeout
  end

  class Request
    
    def self.execute(args, &block)
      #puts "Calling overriden RestClient::Request execute"
      timeouts = {:timeout=>90000000, :open_timeout=>90000000}
      args.merge!(timeouts)
      #puts "Req args #{args}"
      new(args).execute(& block)
    end
    
  end
  
  def self.post(url, payload, headers={}, &block)
    Request.execute(:method => :post,
                    :url => url,
                    :payload => payload,
                    :headers => headers,
                    :timeout=>@timeout,
                    :open_timeout=>@open_timeout,
                    &block)
  end
  
  
end

#RestClient.open_timeout = 90000000
#RestClient.timeout = 90000000
 
