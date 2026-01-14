# frozen_string_literal: true

class UploadAvatarJob < ApplicationJob
  # Retry on transient network errors with exponential backoff
  retry_on AvatarDownloadAndUploadService::DownloadError,
    wait: :exponentially_longer,
    attempts: 5 do |job, error|
      avatar_url = job.arguments.first
      Rails.logger.error("UploadAvatarJob: Failed after max retries - url: #{avatar_url}, error: #{error.message}")
    end

  # Retry on AWS S3 transient errors
  retry_on Aws::S3::Errors::ServiceError,
    wait: :exponentially_longer,
    attempts: 5 do |job, error|
      avatar_url = job.arguments.first
      Rails.logger.error("UploadAvatarJob: Failed after max retries (S3 error) - url: #{avatar_url}, error: #{error.message}")
    end

  # Don't retry on invalid URLs - these are permanent failures
  discard_on AvatarDownloadAndUploadService::InvalidUrlError do |job, error|
    avatar_url = job.arguments.first
    Rails.logger.error("UploadAvatarJob: Discarded (invalid URL) - url: #{avatar_url}, error: #{error.message}")
  end

  # Don't retry on file too large - this is a permanent failure
  discard_on AvatarDownloadAndUploadService::FileTooLargeError do |job, error|
    avatar_url = job.arguments.first
    Rails.logger.error("UploadAvatarJob: Discarded (file too large) - url: #{avatar_url}, error: #{error.message}")
  end

  def perform(avatar_url)
    AvatarDownloadAndUploadService.new.call(avatar_url: avatar_url)
  end
end
