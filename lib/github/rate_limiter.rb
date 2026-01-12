require "json"
require "time"

module Github
  class RateLimiter
    # Default resource type for unauthenticated requests
    DEFAULT_RESOURCE = "core"

    # Buffer time (in seconds) before reset to avoid race conditions
    RESET_BUFFER = 5

    # Minimum sleep time when rate limited (seconds)
    MIN_SLEEP = 1

    attr_reader :storage, :resource

    # Initialize rate limiter with storage backend
    # @param storage [Github::Storage::Interface] Storage backend implementation
    # @param resource [String] GitHub resource type (default: "core")
    def initialize(storage:, resource: DEFAULT_RESOURCE)
      @storage = storage
      @resource = resource
    end

    # Check rate limit before making a request
    # Will sleep/block if rate limit is exhausted
    # @return [void]
    def check_limit
      rate_limit_data = fetch_rate_limit_data

      return unless rate_limit_data # No data yet, allow request

      remaining = rate_limit_data["remaining"].to_i
      reset_time = rate_limit_data["reset"].to_i

      # If we have remaining requests, allow the request
      return if remaining > 0

      # Calculate sleep time until reset
      sleep_duration = calculate_sleep_duration(reset_time)

      # Sleep if we need to wait for reset
      if sleep_duration > 0
        sleep(sleep_duration)
        # Clear the stored data after reset
        clear_rate_limit_data
      end
    end

    # Record rate limit information from response headers
    # @param headers [Hash] HTTP response headers
    # @return [void]
    def record_limit(headers)
      # GitHub uses lowercase header names in Net::HTTP responses
      limit = extract_header(headers, "x-ratelimit-limit")
      remaining = extract_header(headers, "x-ratelimit-remaining")
      reset = extract_header(headers, "x-ratelimit-reset")
      resource_type = extract_header(headers, "x-ratelimit-resource") || resource

      # Only store if we have all required headers
      return unless limit && remaining && reset

      data = {
        "limit" => limit,
        "remaining" => remaining,
        "reset" => reset,
        "resource" => resource_type
      }

      # Calculate TTL: time until reset + buffer
      ttl = calculate_ttl(reset.to_i)

      storage.set(storage_key, JSON.generate(data), ttl: ttl)
    end

    private

    # Fetch rate limit data from storage
    # @return [Hash, nil] Parsed rate limit data or nil
    def fetch_rate_limit_data
      data = storage.get(storage_key)
      return nil unless data

      JSON.parse(data)
    rescue JSON::ParserError
      # If data is corrupted, clear it
      clear_rate_limit_data
      nil
    end

    # Clear rate limit data from storage
    # @return [void]
    def clear_rate_limit_data
      storage.delete(storage_key)
    end

    # Calculate how long to sleep until rate limit resets
    # @param reset_timestamp [Integer] Unix timestamp when limit resets
    # @return [Integer] Seconds to sleep (minimum MIN_SLEEP)
    def calculate_sleep_duration(reset_timestamp)
      now = Time.now.to_i
      duration = reset_timestamp - now + RESET_BUFFER

      # Return at least MIN_SLEEP to avoid tight loops
      [ duration, MIN_SLEEP ].max
    end

    # Calculate TTL for stored data
    # @param reset_timestamp [Integer] Unix timestamp when limit resets
    # @return [Integer] TTL in seconds
    def calculate_ttl(reset_timestamp)
      now = Time.now.to_i
      ttl = reset_timestamp - now + (RESET_BUFFER * 2)

      # Return at least 60 seconds TTL
      [ ttl, 60 ].max
    end

    # Extract header value (case-insensitive)
    # Net::HTTP uses lowercase keys for response headers and returns values as arrays
    # @param headers [Hash] HTTP response headers
    # @param key [String] Header name (lowercase)
    # @return [String, nil] Header value or nil
    def extract_header(headers, key)
      # Try exact match first (lowercase)
      value = headers[key]
      value = value.first if value.is_a?(Array)
      return value if value

      # Try case-insensitive search as fallback
      headers.each do |k, v|
        if k.downcase == key.downcase
          return v.is_a?(Array) ? v.first : v
        end
      end

      nil
    end

    # Generate storage key for this resource
    # @return [String] Storage key
    def storage_key
      "github:rate_limit:#{resource}"
    end
  end
end
