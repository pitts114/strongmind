require "net/http"
require "json"
require "uri"

module Github
  class Client
    # Default configuration constants
    DEFAULT_BASE_URL = "https://api.github.com"
    DEFAULT_API_VERSION = "2022-11-28"
    DEFAULT_TIMEOUT = 10

    # Custom exception hierarchy
    class Error < StandardError
      attr_reader :status_code, :response_body

      def initialize(message, status_code: nil, response_body: nil)
        super(message)
        @status_code = status_code
        @response_body = response_body
      end
    end

    class RateLimitError < Error; end      # 403
    class ServerError < Error; end         # 500/502/503

    # 304 Not Modified is treated as an error since we don't yet implement caching
    # and thus don't have a cached result to provide. When caching is added, this
    # response would indicate we should return cached data. For now, application code
    # can rescue this and handle it as needed (e.g., return empty array).
    class NotModifiedError < Error; end    # 304

    class ClientError < Error; end         # Other 4xx

    attr_reader :base_url, :api_version, :timeout

    # Initialize with optional configuration
    def initialize(base_url: DEFAULT_BASE_URL, api_version: DEFAULT_API_VERSION, timeout: DEFAULT_TIMEOUT)
      @base_url = base_url
      @api_version = api_version
      @timeout = timeout
    end

    # List public events from GitHub
    # @return [Array<Hash>] Array of event hashes
    # @raise [RateLimitError] when rate limit is exceeded
    # @raise [ServerError] on server errors or network failures
    # @raise [ClientError] on client errors
    def list_public_events
      response = make_request(endpoint: "/events")

      case response
      when Net::HTTPSuccess
        parse_response(response: response)
      when Net::HTTPNotModified
        raise NotModifiedError.new(
          "Not modified",
          status_code: response.code.to_i,
          response_body: response.body
        )
      when Net::HTTPForbidden
        raise RateLimitError.new(
          "GitHub API rate limit exceeded",
          status_code: response.code.to_i,
          response_body: response.body
        )
      when Net::HTTPServerError
        raise ServerError.new(
          "GitHub API server error: #{response.code} #{response.message}",
          status_code: response.code.to_i,
          response_body: response.body
        )
      else
        handle_error_response(response: response)
      end
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
      raise ServerError.new("Network error: #{e.message}")
    rescue JSON::ParserError => e
      raise ServerError.new("Invalid JSON response: #{e.message}")
    end

    private

    # Make HTTP GET request to GitHub API
    # @param endpoint [String] API endpoint path
    # @return [Net::HTTPResponse]
    def make_request(endpoint:)
      uri = URI.join(base_url, endpoint)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github+json"
        request["X-GitHub-Api-Version"] = api_version

        http.request(request)
      end
    end

    # Parse successful JSON response
    # @param response [Net::HTTPResponse]
    # @return [Array<Hash>, Hash]
    def parse_response(response:)
      JSON.parse(response.body)
    end

    # Handle error responses by raising appropriate exceptions
    # @param response [Net::HTTPResponse]
    # @raise [ClientError]
    def handle_error_response(response:)
      raise ClientError.new(
        "GitHub API error: #{response.code} #{response.message}",
        status_code: response.code.to_i,
        response_body: response.body
      )
    end
  end
end
