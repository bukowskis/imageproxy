require File.join(File.expand_path(File.dirname(__FILE__)), "command")

require 'RMagick'
require 'rest_client'
require 'digest'
require 'benchmark'

module Imageproxy
  class Convert < Imageproxy::Command
    attr_reader :options

    class ConvertedImage
      attr_reader :image_blob, :source_headers

      def initialize(image_blob, source_headers, options, cache_time, modified = true)
        @modified = modified
        @image_blob, @source_headers, @options, @cache_time = image_blob, source_headers, options, cache_time
      end

      def source_etag
        return false
        if source_headers[:etag]
          match = /(?:W\/)?\"(.*)\"/.match(source_headers[:etag])
          return nil unless match
          match[1]
        end
      end

      def content_type
#        source_headers[:content_type]
        "image/jpeg"
      end

      def empty?
        @image_blob.empty?
      end

      def size
        return 0 if @image_blob.nil?
        @image_blob.bytesize
      end

      def stream
        StringIO.new(@image_blob)
      end

      def cache_header cache_time
        {"Cache-Control" => "public, max-age=#{cache_time}"}
      end

      def cache_header_from_source
        value = source_headers[:cache_control]
        return nil unless value
        max_age = value.scan(/=\s*(\d*)/).flatten.first.to_i
        cache_header max_age
      end

      def headers
        if @cache_time
          headers = cache_header @cache_time
        else
          headers = cache_header_from_source
        end
        headers ||= cache_header 86400

        headers.merge!('Last-Modified' => source_headers[:last_modified] || Time.now.httpdate)

        if modified?
          headers.merge!("Content-Length" => size.to_s,
                         "Content-Type" => content_type)
        end

        if source_etag
          quoted_original_etag = source_etag.tr('"', '')
          # Using weak etag (the prefixed "W"), since the image transformations
          # aren't necessarily byte-to-byte identical
          headers.merge!("ETag" => %{W/"#{quoted_original_etag}-#{transformation_checksum(@options)}"})
        end
        headers
      end

      def transformation_checksum(options)
        buffer = options.keys.sort.collect { |key|
          "#{key}:#{options[key]}"
        }.flatten.join(':')
        Digest::MD5.hexdigest(buffer)[0..8]
      end

      def modified?
        @modified
      end
    end

    def initialize(options, cache_time, requested_etag = nil)
      @options = options
      @cache_time = cache_time
      @requested_etag = requested_etag
      if (!(options.resize || options.thumbnail || options.rotate || options.flip || options.format || options.quality))
        raise "Missing action or illegal parameter value"
      end
    end

    def process_image(original_image)
      image = Magick::Image.from_blob(original_image).first
      image.format = "JPEG"

      if options.resize
        x, y = options.resize.split('x').collect(&:to_i)

        if options.shape == "cut"
          image.crop_resized!(x, y, Magick::CenterGravity)
        else
          image.change_geometry(options.resize) do |proportional_x, proportional_y, img|
            img.resize!(proportional_x, proportional_y)
          end
        end
      end

      image.strip! # Remove EXIF garbage
      image
    end

    def execute(user_agent=nil, timeout=nil)
      user_agent = user_agent || "imageproxy"

      request_options = {
              :timeout => timeout,
              :user_agent => user_agent,
              :accept => '*/*'
      }
      if @requested_etag && @requested_etag =~ %r{^(?:W\/)?"(.+)\-(.*?)"$}
        source_etag = $1
        request_options[:if_none_match] = %{"#{source_etag}"}
      end

      response = image = nil
      Benchmark.bm(16) do |bm|
        bm.report("Download file:") do
          begin
            response = RestClient.get(options.source, request_options)
          rescue RestClient::NotModified => e
            return ConvertedImage.new(nil, e.response.headers, options, @cache_time, false)
          end
        end

        original_image = response.to_str
        bm.report("Process image:") do
          image = process_image(original_image)
        end
      end
      ConvertedImage.new(image.to_blob, response.headers, options, @cache_time)
    end
  end
end
