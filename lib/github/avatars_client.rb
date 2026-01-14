# frozen_string_literal: true

require "net/http"
require "uri"

module Github
  class AvatarsClient
    DEFAULT_TIMEOUT = 30
    MAX_REDIRECTS = 5

    # Custom exception hierarchy
    class Error < StandardError; end
    class DownloadError < Error; end
    class FileSizeExceededError < Error; end

    attr_reader :timeout

    def initialize(timeout: DEFAULT_TIMEOUT)
      @timeout = timeout
    end

    # Fetches headers for a URL without downloading the body
    # @param url [String] Image URL
    # @return [Hash] { content_length: Integer|nil, content_type: String }
    # @raise [DownloadError] if request fails
    def head(url:)
      uri = URI.parse(url)
      fetch_headers(uri: uri, redirect_count: 0)
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
      raise DownloadError, "Network error fetching headers: #{e.message}"
    end

    # Streams image download to provided IO object
    # @param url [String] Image URL
    # @param io [IO] Writable IO object (caller creates/manages this)
    # @param max_size [Integer, nil] Optional max bytes to download
    # @return [Hash] { bytes_written: Integer, content_type: String }
    # @raise [DownloadError] if download fails
    # @raise [FileSizeExceededError] if max_size exceeded during streaming
    def download(url:, io:, max_size: nil)
      uri = URI.parse(url)
      stream_download(uri: uri, io: io, max_size: max_size, redirect_count: 0)
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
      raise DownloadError, "Network error downloading image: #{e.message}"
    end

    private

    def fetch_headers(uri:, redirect_count:)
      raise DownloadError, "Too many redirects" if redirect_count > MAX_REDIRECTS

      response = make_head_request(uri: uri)

      case response
      when Net::HTTPSuccess
        {
          content_length: response["content-length"]&.to_i,
          content_type: extract_content_type(response)
        }
      when Net::HTTPRedirection
        new_uri = URI.parse(response["location"])
        fetch_headers(uri: new_uri, redirect_count: redirect_count + 1)
      else
        raise DownloadError, "HTTP error: #{response.code} #{response.message}"
      end
    end

    def make_head_request(uri:)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: timeout,
        read_timeout: timeout
      ) do |http|
        request = Net::HTTP::Head.new(uri)
        request["Accept"] = "image/*"
        http.request(request)
      end
    end

    def stream_download(uri:, io:, max_size:, redirect_count:)
      raise DownloadError, "Too many redirects" if redirect_count > MAX_REDIRECTS

      result = make_streaming_request(uri: uri, io: io, max_size: max_size)

      case result[:response]
      when Net::HTTPSuccess
        { bytes_written: result[:bytes_written], content_type: extract_content_type(result[:response]) }
      when Net::HTTPRedirection
        new_uri = URI.parse(result[:response]["location"])
        stream_download(uri: new_uri, io: io, max_size: max_size, redirect_count: redirect_count + 1)
      else
        raise DownloadError, "HTTP error: #{result[:response].code} #{result[:response].message}"
      end
    end

    def make_streaming_request(uri:, io:, max_size:)
      bytes_written = 0

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
            bytes_written = stream_body(response: response, io: io, max_size: max_size)
          end
          return { response: response, bytes_written: bytes_written }
        end
      end
    end

    def stream_body(response:, io:, max_size:)
      bytes_written = 0

      response.read_body do |chunk|
        bytes_written += chunk.bytesize

        if max_size && bytes_written > max_size
          raise FileSizeExceededError,
            "File size exceeded maximum allowed #{max_size} bytes during download"
        end

        io.write(chunk)
      end

      bytes_written
    end

    def extract_content_type(response)
      response["content-type"]&.split(";")&.first || "image/png"
    end
  end
end
