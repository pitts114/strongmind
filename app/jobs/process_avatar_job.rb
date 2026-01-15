# frozen_string_literal: true

# NOTE: When a user's avatar changes (e.g., v=4 -> v=5), the old avatar file
# remains in S3 storage but is no longer referenced by any user record.
# This is a known limitation. Future options to address this:
# 1. Create a github_user_avatars table to track all avatar versions
# 2. Implement a cleanup job that removes unreferenced avatar files
# For now, orphaned files are acceptable given low storage costs.

class ProcessAvatarJob < ApplicationJob
  # Exponential backoff: (executions^4) + 2 seconds
  # This matches Rails' :exponentially_longer but avoids compatibility issues with Sidekiq
  EXPONENTIAL_BACKOFF = ->(executions) { ((executions || 1)**4) + 2 }

  # Retry on transient network errors with exponential backoff
  retry_on AvatarDownloadAndStoreService::DownloadError,
    wait: EXPONENTIAL_BACKOFF,
    attempts: 5 do |job, error|
      user_id, avatar_url = job.arguments
      Rails.logger.error("ProcessAvatarJob: Failed after max retries - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
    end

  # Retry on AWS S3 transient errors
  retry_on Aws::S3::Errors::ServiceError,
    wait: EXPONENTIAL_BACKOFF,
    attempts: 5 do |job, error|
      user_id, avatar_url = job.arguments
      Rails.logger.error("ProcessAvatarJob: Failed after max retries (S3 error) - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
    end

  # Don't retry on invalid URLs - these are permanent failures
  discard_on AvatarDownloadAndStoreService::InvalidUrlError do |job, error|
    user_id, avatar_url = job.arguments
    Rails.logger.error("ProcessAvatarJob: Discarded (invalid URL) - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
  end

  # Don't retry on file too large - this is a permanent failure
  discard_on AvatarDownloadAndStoreService::FileTooLargeError do |job, error|
    user_id, avatar_url = job.arguments
    Rails.logger.error("ProcessAvatarJob: Discarded (file too large) - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
  end

  def perform(user_id, avatar_url)
    ProcessAvatarService.new.call(user_id: user_id, avatar_url: avatar_url)
  end
end
