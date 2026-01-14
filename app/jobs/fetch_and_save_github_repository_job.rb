class FetchAndSaveGithubRepositoryJob < ApplicationJob
  # Retry on transient errors with exponential backoff
  retry_on Github::Client::ServerError, wait: :exponentially_longer, attempts: 5 do |job, error|
    owner, repo_name = job.arguments
    Rails.logger.error("FetchAndSaveGithubRepositoryJob: Failed after max retries (server error) - repo: #{owner}/#{repo_name}, error: #{error.message}")
  end

  # Retry on rate limits with long delay
  retry_on Github::Client::RateLimitError, wait: 1.hour, attempts: 3 do |job, error|
    owner, repo_name = job.arguments
    Rails.logger.error("FetchAndSaveGithubRepositoryJob: Failed after max retries (rate limit) - repo: #{owner}/#{repo_name}")
  end

  # Don't retry on permanent errors (404 = deleted, 403 = private repo)
  discard_on Github::Client::ClientError do |job, error|
    owner, repo_name = job.arguments
    Rails.logger.error("FetchAndSaveGithubRepositoryJob: Discarded (client error) - repo: #{owner}/#{repo_name}, error: #{error.message}, status: #{error.status_code}")
  end

  def perform(owner, repo_name)
    GithubRepositoryFetcher.new.call(owner: owner, repo: repo_name)
  end
end
