# Global Redis instance for application use (rate limiting, caching, etc.)
# Sidekiq has its own Redis configuration in config/initializers/sidekiq.rb
REDIS = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
