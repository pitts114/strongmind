# frozen_string_literal: true

# NOTE: When a user's avatar changes (e.g., v=4 -> v=5), the old avatar file
# remains in S3 storage but is no longer referenced by any user record.
# This is a known limitation. Future options to address this:
# 1. Create a github_user_avatars table to track all avatar versions
# 2. Implement a cleanup job that removes unreferenced avatar files
# For now, orphaned files are acceptable given low storage costs.

class UploadAvatarJob < ApplicationJob
  # Retry on transient network errors with exponential backoff
  retry_on AvatarDownloadAndUploadService::DownloadError,
    wait: :exponentially_longer,
    attempts: 5 do |job, error|
      user_id, avatar_url = job.arguments
      Rails.logger.error("UploadAvatarJob: Failed after max retries - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
    end

  # Retry on AWS S3 transient errors
  retry_on Aws::S3::Errors::ServiceError,
    wait: :exponentially_longer,
    attempts: 5 do |job, error|
      user_id, avatar_url = job.arguments
      Rails.logger.error("UploadAvatarJob: Failed after max retries (S3 error) - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
    end

  # Don't retry on invalid URLs - these are permanent failures
  discard_on AvatarDownloadAndUploadService::InvalidUrlError do |job, error|
    user_id, avatar_url = job.arguments
    Rails.logger.error("UploadAvatarJob: Discarded (invalid URL) - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
  end

  # Don't retry on file too large - this is a permanent failure
  discard_on AvatarDownloadAndUploadService::FileTooLargeError do |job, error|
    user_id, avatar_url = job.arguments
    Rails.logger.error("UploadAvatarJob: Discarded (file too large) - user_id: #{user_id}, url: #{avatar_url}, error: #{error.message}")
  end

  def perform(user_id, avatar_url)
    result = AvatarDownloadAndUploadService.new.call(avatar_url: avatar_url)

    if result[:uploaded] || result[:skipped]
      GithubUser.find(user_id).update!(avatar_key: result[:key])
      Rails.logger.info("UploadAvatarJob: Updated avatar_key for user #{user_id} - key: #{result[:key]}")
    end
  end
end
