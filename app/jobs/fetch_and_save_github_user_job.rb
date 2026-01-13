class FetchAndSaveGithubUserJob < ApplicationJob
  # Retry on transient errors with exponential backoff
  retry_on Github::Client::ServerError, wait: :exponentially_longer, attempts: 5

  # Retry on rate limits with long delay (GitHub rate limit window is ~1 hour)
  retry_on Github::Client::RateLimitError, wait: 1.hour, attempts: 3

  # Don't retry on permanent errors (404 = user deleted, 403 = access denied)
  discard_on Github::Client::ClientError

  def perform(username)
    GithubUserFetcher.new.call(username: username)
  end
end
