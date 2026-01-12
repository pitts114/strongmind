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
    end
  end
end
