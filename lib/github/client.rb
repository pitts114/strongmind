require "net/http"
require "json"
require "uri"
require_relative "storage"
require_relative "storage/memory"
require_relative "rate_limiter"

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

    attr_reader :base_url, :api_version, :timeout, :rate_limiter

    # Initialize with optional configuration
    # @param base_url [String] GitHub API base URL
    # @param api_version [String] GitHub API version
    # @param timeout [Integer] Request timeout in seconds
    # @param storage [Github::Storage::Interface, nil] Storage backend for rate limiting
    # @param rate_limit_resource [String] GitHub resource type for rate limiting
    def initialize(
      base_url: DEFAULT_BASE_URL,
      api_version: DEFAULT_API_VERSION,
      timeout: DEFAULT_TIMEOUT,
      storage: Storage::Memory.new,
      rate_limit_resource: RateLimiter::DEFAULT_RESOURCE
    )
      @base_url = base_url
      @api_version = api_version
      @timeout = timeout

      @rate_limiter = RateLimiter.new(
        storage: storage,
        resource: rate_limit_resource
      )
    end

    # List public events from GitHub
    # @return [Array<Hash>] Array of event hashes
    # @raise [RateLimitError] when rate limit is exceeded (legacy - now we sleep instead)
    # @raise [ServerError] on server errors or network failures
    # @raise [ClientError] on client errors
    def list_public_events
      execute_request(endpoint: "/events")
    end

    # Fetch a specific GitHub user by username
    # @param username [String] GitHub username (e.g., "octocat")
    # @return [Hash] User data hash
    # @raise [RateLimitError] when rate limit is exceeded (legacy - now we sleep instead)
    # @raise [ServerError] on server errors or network failures
    # @raise [ClientError] on client errors (e.g., 404 user not found)
    def get_user(username:)
      execute_request(endpoint: "/users/#{username}")
    end

    # Fetch a specific GitHub repository
    # @param owner [String] Repository owner (username or org name)
    # @param repo [String] Repository name
    # @return [Hash] Repository data hash
    # @raise [RateLimitError] when rate limit is exceeded (legacy - now we sleep instead)
    # @raise [ServerError] on server errors or network failures
    # @raise [ClientError] on client errors (e.g., 404 repo not found)
    def get_repository(owner:, repo:)
      execute_request(endpoint: "/repos/#{owner}/#{repo}")
    end

    private

    # Execute an API request with rate limiting and error handling
    # @param endpoint [String] API endpoint path
    # @return [Array<Hash>, Hash] Parsed JSON response
    # @raise [RateLimitError] when rate limit is exceeded
    # @raise [ServerError] on server errors or network failures
    # @raise [ClientError] on client errors
    # @raise [NotModifiedError] when resource hasn't changed (304)
    def execute_request(endpoint:)
      # Check rate limit before making request (may sleep)
      rate_limiter.check_limit

      response = make_request(endpoint: endpoint)

      # Record rate limit info from response
      rate_limiter.record_limit(response.to_hash)

      handle_response(response: response)
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
      raise ServerError.new("Network error: #{e.message}")
    rescue JSON::ParserError => e
      raise ServerError.new("Invalid JSON response: #{e.message}")
    end

    # Handle HTTP response and raise appropriate errors
    # @param response [Net::HTTPResponse]
    # @return [Array<Hash>, Hash] Parsed JSON response on success
    # @raise [RateLimitError, ServerError, ClientError, NotModifiedError]
    def handle_response(response:)
      case response
      when Net::HTTPSuccess
        parse_response(response: response)
      when Net::HTTPNotModified
        raise NotModifiedError.new(
          "Not modified",
          status_code: response.code.to_i,
          response_body: response.body
        )
      when Net::HTTPTooManyRequests
        # 429 always indicates rate limiting (primary or secondary)
        raise RateLimitError.new(
          "GitHub API rate limit exceeded",
          status_code: response.code.to_i,
          response_body: response.body
        )
      when Net::HTTPForbidden
        # 403 can be rate limiting OR access denied
        if rate_limit_exceeded?(response)
          raise RateLimitError.new(
            "GitHub API rate limit exceeded",
            status_code: response.code.to_i,
            response_body: response.body
          )
        else
          # Regular forbidden error (e.g., private repo, insufficient permissions)
          raise ClientError.new(
            "GitHub API error: #{response.code} #{response.message}",
            status_code: response.code.to_i,
            response_body: response.body
          )
        end
      when Net::HTTPServerError
        raise ServerError.new(
          "GitHub API server error: #{response.code} #{response.message}",
          status_code: response.code.to_i,
          response_body: response.body
        )
      else
        handle_error_response(response: response)
      end
    end

    # Check if a 403 response is due to rate limiting
    # GitHub can return 403 for both rate limiting and access denied
    # @param response [Net::HTTPResponse]
    # @return [Boolean] true if rate limit is exceeded
    def rate_limit_exceeded?(response)
      # Primary rate limit: X-RateLimit-Remaining header is 0
      remaining = response["x-ratelimit-remaining"]
      return true if remaining && remaining.to_i == 0

      # Secondary rate limit: check for retry-after header or rate limit message
      return true if response["retry-after"]

      # Fallback: check response body for rate limit message
      return false unless response.body

      begin
        body = JSON.parse(response.body)
        body["message"]&.match?(/rate limit/i)
      rescue JSON::ParserError
        false
      end
    end

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
