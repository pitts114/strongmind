# frozen_string_literal: true

require "net/http"
require "uri"
require "tempfile"

module Github
  class AvatarsClient
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_FILE_SIZE = 10 * 1024 * 1024 # 10 MB
    MAX_REDIRECTS = 5

    # Custom exception hierarchy
    class Error < StandardError; end
    class DownloadError < Error; end
    class FileTooLargeError < Error; end

    attr_reader :timeout, :max_file_size

    def initialize(timeout: DEFAULT_TIMEOUT, max_file_size: DEFAULT_MAX_FILE_SIZE)
      @timeout = timeout
      @max_file_size = max_file_size
    end

    # Downloads image from URL to a temp file
    # @param url [String] Image URL (should already be validated)
    # @return [Hash] { temp_file: Tempfile, content_type: String }
    # @raise [DownloadError] if download fails
    # @raise [FileTooLargeError] if file exceeds max size
    def download(url:)
      uri = URI.parse(url)
      temp_file = Tempfile.new(["avatar", ".tmp"], binmode: true)

      begin
        stream_download(uri: uri, temp_file: temp_file, redirect_count: 0)
      rescue => e
        cleanup_temp_file(temp_file)
        raise
      end
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
      raise DownloadError, "Network error downloading image: #{e.message}"
    end

    private

    def stream_download(uri:, temp_file:, redirect_count:)
      raise DownloadError, "Too many redirects" if redirect_count > MAX_REDIRECTS

      response = make_streaming_request(uri: uri, temp_file: temp_file)

      case response
      when Net::HTTPSuccess
        temp_file.rewind
        { temp_file: temp_file, content_type: extract_content_type(response) }
      when Net::HTTPRedirection
        cleanup_temp_file(temp_file)
        new_uri = URI.parse(response["location"])
        new_temp_file = Tempfile.new(["avatar", ".tmp"], binmode: true)
        stream_download(uri: new_uri, temp_file: new_temp_file, redirect_count: redirect_count + 1)
      else
        raise DownloadError, "HTTP error: #{response.code} #{response.message}"
      end
    end

    def make_streaming_request(uri:, temp_file:)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: timeout,
        read_timeout: timeout
      ) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "image/*"

        http.request(request) do |response|
          if response.is_a?(Net::HTTPSuccess)
            check_content_length(response)
            stream_body(response: response, temp_file: temp_file)
          end
          return response
        end
      end
    end

    def check_content_length(response)
      content_length = response["content-length"]&.to_i
      return unless content_length && content_length > 0

      if content_length > max_file_size
        raise FileTooLargeError,
          "File size #{content_length} bytes exceeds maximum allowed #{max_file_size} bytes"
      end
    end

    def stream_body(response:, temp_file:)
      bytes_written = 0

      response.read_body do |chunk|
        bytes_written += chunk.bytesize

        if bytes_written > max_file_size
          raise FileTooLargeError,
            "File size exceeded maximum allowed #{max_file_size} bytes during download"
        end

        temp_file.write(chunk)
      end
    end

    def extract_content_type(response)
      response["content-type"]&.split(";")&.first || "image/png"
    end

    def cleanup_temp_file(temp_file)
      return unless temp_file

      temp_file.close unless temp_file.closed?
      temp_file.unlink if temp_file.path && File.exist?(temp_file.path)
    rescue => e
      # Log warning but don't raise - cleanup is best effort
    end
  end
end
