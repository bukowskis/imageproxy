require File.join(File.expand_path(File.dirname(__FILE__)), "options")
require File.join(File.expand_path(File.dirname(__FILE__)), "convert")
require File.join(File.expand_path(File.dirname(__FILE__)), "selftest")
require File.join(File.expand_path(File.dirname(__FILE__)), "signature")
require 'uri'
require 'newrelic_rpm'
require 'new_relic/agent/instrumentation/rack'

module Imageproxy
  class Server
    def initialize
      @file_server = Rack::File.new(File.join(File.expand_path(File.dirname(__FILE__)), "..", "public"))
    end

    def call(env)
      request = Rack::Request.new(env)
      options = Options.new(request.path_info, request.params)
      user_agent = request.env["HTTP_USER_AGENT"]

      case options.command
        when "crossdomain.xml"
          xml ='<?xml version="1.0"?>
<!DOCTYPE cross-domain-policy SYSTEM "http://www.macromedia.com/xml/dtds/cross-domain-policy.dtd">
<cross-domain-policy>
  <allow-access-from domain="*" />
</cross-domain-policy>'
          [200, {"Content-Type" => "application/xml"}, [xml]]
        when "convert", "process", nil
          check_signature request, options
          check_domain options
          check_size options

          requested_etag = request.env['HTTP_IF_NONE_MATCH']
          converted_image = Convert.new(options, config(:cache_time), requested_etag).execute(user_agent, config(:timeout))
          if converted_image.modified?
            raise "Empty image file" if converted_image.empty?
            STDERR.puts "OK: command=#{options.command} url=#{options.source} ua=\"#{user_agent}\""
            [200, converted_image.headers, converted_image.stream]
          else
            [304, converted_image.headers]
          end
        when "selftest"
          [200, {"Content-Type" => "text/html"}, [Selftest.html(request, config?(:signature_required), config(:signature_secret))]]
        else
          @file_server.call(env)
      end
    rescue
      STDERR.puts "ERR: command=#{options.command} url=#{options.source} error=\"#{$!}\""
      STDERR.puts $!
      STDERR.puts $!.backtrace.join("\n")
      [500, {"Content-Type" => "text/plain"}, ["Error (#{$!})"]]
    end
    # Do the include after the call method is defined:
    include NewRelic::Agent::Instrumentation::Rack
    private

    def config(symbol)
      ENV["IMAGEPROXY_#{symbol.to_s.upcase}"]
    end

    def config?(symbol)
      config(symbol) && config(symbol).casecmp("TRUE") == 0
    end

    def check_signature(request, options)
      if config?(:signature_required)
        raise "Missing signature" if options.signature.nil?

        valid_signature = Signature.correct?(options.signature, request.fullpath, config(:signature_secret))
        raise "Invalid signature #{options.signature} for #{request.url}" unless valid_signature
      end
    end

    def check_domain(options)
      raise "Invalid domain" unless domain_allowed? options.source
    end

    def check_size(options)
      raise "Image size too large" if exceeds_max_size(options.resize, options.thumbnail)
    end

    def domain_allowed?(url)
      return true unless allowed_domains
      allowed_domains.include?(url_to_domain url)
    end

    def url_to_domain(url)
      URI::parse(url).host.split(".")[-2, 2].join(".")
    rescue
      ""
    end

    def allowed_domains
      config(:allowed_domains) && config(:allowed_domains).split(",").map(&:strip)
    end

    def exceeds_max_size(*sizes)
      max_size && sizes.any? { |size| size && requested_size(size) > max_size }
    end

    def max_size
      config(:max_size) && config(:max_size).to_i
    end

    def requested_size(req_size)
      sizes = req_size.scan(/\d*/)
      if sizes[2] && (sizes[2].to_i > sizes[0].to_i)
        sizes[2].to_i
      else
        sizes[0].to_i
      end
    end
  end
end
