class FetchAndSaveGithubRepositoryJob < ApplicationJob
  # Retry on transient errors with exponential backoff
  retry_on Github::Client::ServerError, wait: :exponentially_longer, attempts: 5

  # Retry on rate limits with long delay
  retry_on Github::Client::RateLimitError, wait: 1.hour, attempts: 3

  # Don't retry on permanent errors (404 = deleted, 403 = private repo)
  discard_on Github::Client::ClientError

  # Retry on database errors
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3

  def perform(owner, repo_name)
    GithubRepositoryFetcher.new.call(owner: owner, repo: repo_name)
  end
end
