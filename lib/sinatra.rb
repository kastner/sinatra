require "rubygems"
require "rack"
require "uri"

class Object
  def tap
    yield self
    self
  end
end

module Sinatra

  class EventContext
    
    attr_reader :request, :response
    
    def initialize(env)
      @request = Rack::Request.new(env)
      @response = Rack::Response.new
    end
    
    def status(code = nil)
      @response.status = code if code
      @response.status
    end
    
    def run_block(&b)
      tap { |c| c.body = instance_eval(&b) }
    end
    alias :body :run_block
    
    def method_missing(sym, *args, &b)
      @response.send(sym, *args, &b)
    end
    
  end
  
  class Event
    
    URI_CHAR = '[^/?:,&#\.]'.freeze unless defined?(URI_CHAR)
    PARAM = /(:(#{URI_CHAR}+)|\*)/.freeze unless defined?(PARAM)
    SPLAT = /(.*?)/
    
    attr_reader :params
    
    def initialize(method, path, &b)
      @method = method.to_sym
      @path   = URI.encode(path)
      @block  = b
      raise "Event needs a block on initialize" unless b
      build_route
    end
    
    def build_route
      @param_keys = []
      @params = {}
      regex = @path.to_s.gsub(PARAM) do |match|
        @param_keys << $2
        "(#{URI_CHAR}+)"
      end
      @pattern = /^#{regex}$/
    end
    
    def call(env)
      context = EventContext.new(env)
      result = catch(:halt) do
        invoke(context)
        nil
      end
      result.to_result(context) if result
      context.finish
    end
    
    def invoke(context)
      context.status(99)
      return unless @method == context.request.request_method.downcase.to_sym
      return unless @pattern =~ context.request.path_info
      @params.merge!(@param_keys.zip($~.captures.map(&:from_param)).to_hash)
      context.status(200)
      context.body(&@block)
    end
    
  end
    
  class Application
    
    module DSL

      def event(method, path, &b)
        apps << Event.new(method, path, &b)
      end
      
      def head(path, &b)
        event(:head, path, &b)
      end

      def get(path, &b)
        event(:get, path, &b)
      end

      def post(path, &b)
        event(:post, path, &b)
      end
      
      def put(path, &b)
        event(:put, path, &b)
      end
      
      def delete(path, &b)
        event(:delete, path, &b)
      end
      
    end
    include DSL

    def initialize(&b)
      @apps = []
      instance_eval(&b)
    end
    
    attr_reader :apps

    def call(env)
      Rack::Cascade.new(apps, 99).call(env)
    end
    
  end
  
end

module Rack

  module Utils
    extend self
  end
  
end

class Array
  
  def to_hash
    self.inject({}) { |h, (k, v)|  h[k] = v; h }
  end
  
  def to_proc
    Proc.new { |*args| args.shift.__send__(self[0], *(args + self[1..-1])) }
  end
  
end

class String

  # Converts +self+ to an escaped URI parameter value
  #   'Foo Bar'.to_param # => 'Foo%20Bar'
  def to_param
    Rack::Utils.escape(self)
  end
  alias :http_escape :to_param
  
  # Converts +self+ from an escaped URI parameter value
  #   'Foo%20Bar'.from_param # => 'Foo Bar'
  def from_param
    Rack::Utils.unescape(self)
  end
  alias :http_unescape :from_param
  
end

class Symbol
  
  def to_proc 
    Proc.new { |*args| args.shift.__send__(self, *args) }
  end
  
end
