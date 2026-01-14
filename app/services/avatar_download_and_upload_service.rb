# frozen_string_literal: true

require "github/avatars_client"

class AvatarDownloadAndUploadService
  class Error < StandardError; end
  class DownloadError < Error; end
  class InvalidUrlError < Error; end
  class FileTooLargeError < Error; end

  def initialize(
    storage: AvatarStorage::S3.new,
    client: Github::AvatarsClient.new,
    key_deriver: AvatarKeyDeriver.new
  )
    @storage = storage
    @client = client
    @key_deriver = key_deriver
  end

  # Downloads an avatar from URL and uploads to S3 storage idempotently
  # @param avatar_url [String] GitHub avatar URL
  # @return [Hash] Result with :key, :uploaded (boolean), and :skipped (boolean)
  # @raise [InvalidUrlError] if URL is invalid or not a GitHub avatar URL
  # @raise [DownloadError] if download fails
  # @raise [FileTooLargeError] if file exceeds max size
  def call(avatar_url:)
    key = derive_key(avatar_url)

    if storage.exists?(key: key)
      Rails.logger.info("AvatarDownloadAndUploadService: Avatar already exists, skipping - key: #{key}")
      return { key: key, uploaded: false, skipped: true }
    end

    download_and_upload(avatar_url: avatar_url, key: key)
  end

  private

  attr_reader :storage, :client, :key_deriver

  def derive_key(avatar_url)
    key_deriver.call(url: avatar_url)
  rescue AvatarKeyDeriver::InvalidUrlError => e
    raise InvalidUrlError, e.message
  end

  def download_and_upload(avatar_url:, key:)
    Rails.logger.info("AvatarDownloadAndUploadService: Downloading avatar - url: #{avatar_url}")

    result = client.download(url: avatar_url)
    temp_file = result[:temp_file]
    content_type = result[:content_type]

    begin
      Rails.logger.info("AvatarDownloadAndUploadService: Uploading avatar - key: #{key}, content_type: #{content_type}")
      storage.upload(key: key, body: temp_file, content_type: content_type)

      Rails.logger.info("AvatarDownloadAndUploadService: Avatar uploaded successfully - key: #{key}")
      { key: key, uploaded: true, skipped: false }
    ensure
      cleanup_temp_file(temp_file)
    end
  rescue Github::AvatarsClient::DownloadError => e
    raise DownloadError, e.message
  rescue Github::AvatarsClient::FileTooLargeError => e
    raise FileTooLargeError, e.message
  end

  def cleanup_temp_file(temp_file)
    return unless temp_file

    temp_file.close unless temp_file.closed?
    temp_file.unlink if temp_file.path && File.exist?(temp_file.path)
  rescue => e
    Rails.logger.warn("AvatarDownloadAndUploadService: Failed to cleanup temp file: #{e.message}")
  end
end
