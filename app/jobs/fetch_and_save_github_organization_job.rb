class FetchAndSaveGithubOrganizationJob < ApplicationJob
  # Retry on transient errors with exponential backoff
  retry_on Github::Client::ServerError, wait: :exponentially_longer, attempts: 5 do |job, error|
    org = job.arguments.first
    Rails.logger.error("FetchAndSaveGithubOrganizationJob: Failed after max retries (server error) - org: #{org}, error: #{error.message}")
  end

  # Retry on rate limits with long delay (GitHub rate limit window is ~1 hour)
  retry_on Github::Client::RateLimitError, wait: 1.hour, attempts: 3 do |job, error|
    org = job.arguments.first
    Rails.logger.error("FetchAndSaveGithubOrganizationJob: Failed after max retries (rate limit) - org: #{org}")
  end

  # Don't retry on permanent errors (404 = organization deleted, 403 = access denied)
  discard_on Github::Client::ClientError do |job, error|
    org = job.arguments.first
    Rails.logger.error("FetchAndSaveGithubOrganizationJob: Discarded (client error) - org: #{org}, error: #{error.message}, status: #{error.status_code}")
  end

  def perform(org)
    GithubOrganizationFetcher.new.call(org: org)
  end
end
