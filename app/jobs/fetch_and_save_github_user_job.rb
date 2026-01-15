class FetchAndSaveGithubUserJob < ApplicationJob
  # Exponential backoff: (executions^4) + 2 seconds
  # This matches Rails' :exponentially_longer but avoids compatibility issues with Sidekiq
  EXPONENTIAL_BACKOFF = ->(executions) { ((executions || 1)**4) + 2 }

  # Retry on transient errors with exponential backoff
  retry_on Github::Client::ServerError, wait: EXPONENTIAL_BACKOFF, attempts: 5 do |job, error|
    username = job.arguments.first
    Rails.logger.error("FetchAndSaveGithubUserJob: Failed after max retries (server error) - username: #{username}, error: #{error.message}")
  end

  # Retry on rate limits with long delay (GitHub rate limit window is ~1 hour)
  retry_on Github::Client::RateLimitError, wait: 1.hour, attempts: 3 do |job, error|
    username = job.arguments.first
    Rails.logger.error("FetchAndSaveGithubUserJob: Failed after max retries (rate limit) - username: #{username}")
  end

  # Don't retry on permanent errors (404 = user deleted, 403 = access denied)
  discard_on Github::Client::ClientError do |job, error|
    username = job.arguments.first
    Rails.logger.error("FetchAndSaveGithubUserJob: Discarded (client error) - username: #{username}, error: #{error.message}, status: #{error.status_code}")
  end

  def perform(username)
    GithubUserFetcher.new.call(username: username)
  end
end
