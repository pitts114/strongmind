# frozen_string_literal: true

require "github/avatars_client"
require "tmpdir"

class AvatarDownloadAndUploadService
  class Error < StandardError; end
  class DownloadError < Error; end
  class InvalidUrlError < Error; end
  class FileTooLargeError < Error; end

  MAX_FILE_SIZE = 10 * 1024 * 1024 # 10 MB

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

    check_file_size(avatar_url: avatar_url)
    download_and_upload(avatar_url: avatar_url, key: key)
  end

  private

  attr_reader :storage, :client, :key_deriver

  def derive_key(avatar_url)
    key_deriver.call(url: avatar_url)
  rescue AvatarKeyDeriver::InvalidUrlError => e
    raise InvalidUrlError, e.message
  end

  def check_file_size(avatar_url:)
    Rails.logger.info("AvatarDownloadAndUploadService: Checking file size - url: #{avatar_url}")

    headers = client.head(url: avatar_url)
    content_length = headers[:content_length]

    validate_file_size!(content_length)
  rescue Github::AvatarsClient::DownloadError => e
    raise DownloadError, e.message
  end

  def validate_file_size!(content_length)
    return unless content_length && content_length > MAX_FILE_SIZE

    raise FileTooLargeError,
      "File size #{content_length} bytes exceeds maximum allowed #{MAX_FILE_SIZE} bytes"
  end

  def download_and_upload(avatar_url:, key:)
    Rails.logger.info("AvatarDownloadAndUploadService: Downloading avatar - url: #{avatar_url}")

    Dir.mktmpdir("avatar") do |dir|
      temp_path = File.join(dir, "avatar.tmp")
      content_type = download_to_file(avatar_url: avatar_url, path: temp_path)

      Rails.logger.info("AvatarDownloadAndUploadService: Uploading avatar - key: #{key}, content_type: #{content_type}")

      File.open(temp_path, "rb") do |file|
        storage.upload(key: key, body: file, content_type: content_type)
      end

      Rails.logger.info("AvatarDownloadAndUploadService: Avatar uploaded successfully - key: #{key}")
      return { key: key, uploaded: true, skipped: false }
    end
    # Directory and file automatically cleaned up when block exits
  end

  def download_to_file(avatar_url:, path:)
    File.open(path, "wb") do |file|
      result = client.download(url: avatar_url, io: file, max_size: MAX_FILE_SIZE)
      return result[:content_type]
    end
  rescue Github::AvatarsClient::DownloadError => e
    raise DownloadError, e.message
  rescue Github::AvatarsClient::FileSizeExceededError => e
    raise FileTooLargeError, e.message
  end
end
