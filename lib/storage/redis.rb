module Storage
  # Redis-backed storage implementation
  class Redis < Github::Storage::Interface
    attr_reader :redis

    # Initialize with Redis connection
    # @param redis [Redis, ConnectionPool] Redis client or connection pool
    def initialize(redis:)
      @redis = redis
    end

    # Get a value by key
    # @param key [String] The storage key
    # @return [String, nil] The stored value or nil if not found
    def get(key)
      with_redis do |conn|
        conn.get(key)
      end
    end

    # Set a value for a key with optional TTL
    # @param key [String] The storage key
    # @param value [String] The value to store
    # @param ttl [Integer, nil] Time to live in seconds (optional)
    # @return [void]
    def set(key, value, ttl: nil)
      with_redis do |conn|
        if ttl
          conn.setex(key, ttl, value)
        else
          conn.set(key, value)
        end
      end
    end

    # Delete a key
    # @param key [String] The storage key
    # @return [void]
    def delete(key)
      with_redis do |conn|
        conn.del(key)
      end
    end

    # Atomically increment a counter
    # @param key [String] The storage key
    # @param amount [Integer] Amount to increment by (default: 1)
    # @return [Integer] The new value after incrementing
    def increment(key, amount: 1)
      with_redis do |conn|
        conn.incrby(key, amount)
      end
    end

    # Atomically decrement a counter
    # @param key [String] The storage key
    # @param amount [Integer] Amount to decrement by (default: 1)
    # @return [Integer] The new value after decrementing
    def decrement(key, amount: 1)
      with_redis do |conn|
        # Use Lua script to ensure we don't go below 0
        script = <<~LUA
          local current = tonumber(redis.call('get', KEYS[1]) or 0)
          local amount = tonumber(ARGV[1])
          local new_value = math.max(current - amount, 0)
          redis.call('set', KEYS[1], new_value)
          return new_value
        LUA

        conn.eval(script, keys: [ key ], argv: [ amount ])
      end
    end

    private

    # Execute block with Redis connection
    # Handles both direct Redis clients and ConnectionPool
    # @yield [Redis] Redis connection
    # @return [Object] Result of block
    def with_redis(&block)
      if redis.respond_to?(:with)
        # ConnectionPool
        redis.with(&block)
      else
        # Direct Redis client
        yield redis
      end
    end
  end
end
