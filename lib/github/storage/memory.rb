require "monitor"

module Github
  module Storage
    # Thread-safe in-memory storage implementation
    # Suitable for single-process applications without Redis
    class Memory < Interface
      def initialize
        @store = {}
        @monitor = Monitor.new
      end

      # Get a value by key
      # @param key [String] The storage key
      # @return [String, nil] The stored value or nil if not found/expired
      def get(key)
        @monitor.synchronize do
          entry = @store[key]
          return nil unless entry

          # Check if expired
          if entry[:expires_at] && Time.now.to_i >= entry[:expires_at]
            @store.delete(key)
            return nil
          end

          entry[:value]
        end
      end

      # Set a value for a key with optional TTL
      # @param key [String] The storage key
      # @param value [String] The value to store
      # @param ttl [Integer, nil] Time to live in seconds (optional)
      # @return [void]
      def set(key, value, ttl: nil)
        @monitor.synchronize do
          expires_at = ttl ? Time.now.to_i + ttl : nil
          @store[key] = {
            value: value,
            expires_at: expires_at
          }
        end
      end

      # Delete a key
      # @param key [String] The storage key
      # @return [void]
      def delete(key)
        @monitor.synchronize do
          @store.delete(key)
        end
      end

      # Clear all stored data (useful for testing)
      # @return [void]
      def clear
        @monitor.synchronize do
          @store.clear
        end
      end
    end
  end
end
