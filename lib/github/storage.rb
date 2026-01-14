module Github
  module Storage
    # Abstract interface for rate limit storage backends
    # Implementations must provide get, set, and delete operations
    class Interface
      # Get a value by key
      # @param key [String] The storage key
      # @return [String, nil] The stored value or nil if not found
      def get(key)
        raise NotImplementedError, "#{self.class} must implement #get"
      end

      # Set a value for a key with optional TTL
      # @param key [String] The storage key
      # @param value [String] The value to store
      # @param ttl [Integer, nil] Time to live in seconds (optional)
      # @return [void]
      def set(key, value, ttl: nil)
        raise NotImplementedError, "#{self.class} must implement #set"
      end

      # Delete a key
      # @param key [String] The storage key
      # @return [void]
      def delete(key)
        raise NotImplementedError, "#{self.class} must implement #delete"
      end

      # Atomically increment a counter
      # @param key [String] The storage key
      # @param amount [Integer] Amount to increment by (default: 1)
      # @return [Integer] The new value after incrementing
      def increment(key, amount: 1)
        raise NotImplementedError, "#{self.class} must implement #increment"
      end

      # Atomically decrement a counter
      # @param key [String] The storage key
      # @param amount [Integer] Amount to decrement by (default: 1)
      # @return [Integer] The new value after decrementing
      def decrement(key, amount: 1)
        raise NotImplementedError, "#{self.class} must implement #decrement"
      end
    end
  end
end
