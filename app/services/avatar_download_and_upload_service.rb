# frozen_string_literal: true

require "net/http"
require "uri"
require "tempfile"

class AvatarDownloadAndUploadService
  DEFAULT_TIMEOUT = 30

  class Error < StandardError; end
  class DownloadError < Error; end
  class InvalidUrlError < Error; end

  CONTENT_TYPE_EXTENSIONS = {
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp"
  }.freeze

  def initialize(storage: AvatarStorage::S3.new, timeout: DEFAULT_TIMEOUT)
    @storage = storage
    @timeout = timeout
  end

  # Downloads an avatar from URL and uploads to S3 storage idempotently
  # @param avatar_url [String] GitHub avatar URL
  # @return [Hash] Result with :key, :uploaded (boolean), and :skipped (boolean)
  # @raise [InvalidUrlError] if URL is invalid or not a GitHub avatar URL
  # @raise [DownloadError] if download fails
  def call(avatar_url:)
    validate_url!(avatar_url)

    key = derive_key(avatar_url)

    if storage.exists?(key: key)
      Rails.logger.info("AvatarDownloadAndUploadService: Avatar already exists, skipping - key: #{key}")
      return { key: key, uploaded: false, skipped: true }
    end

    Rails.logger.info("AvatarDownloadAndUploadService: Downloading avatar - url: #{avatar_url}")
    image_data, content_type = download_avatar(avatar_url)

    Rails.logger.info("AvatarDownloadAndUploadService: Uploading avatar - key: #{key}, content_type: #{content_type}")
    storage.upload(key: key, body: image_data, content_type: content_type)

    Rails.logger.info("AvatarDownloadAndUploadService: Avatar uploaded successfully - key: #{key}")
    { key: key, uploaded: true, skipped: false }
  end

  private

  attr_reader :storage, :timeout

  # Validates that the URL is a valid GitHub avatar URL
  # @param url [String]
  # @raise [InvalidUrlError] if URL is invalid
  def validate_url!(url)
    uri = URI.parse(url)

    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      raise InvalidUrlError, "Invalid URL scheme: #{url}"
    end

    unless uri.host&.match?(/\A(avatars\.)?githubusercontent\.com\z/)
      raise InvalidUrlError, "Not a GitHub avatar URL: #{url}"
    end

    true
  rescue URI::InvalidURIError => e
    raise InvalidUrlError, "Invalid URL: #{e.message}"
  end

  # Derives a deterministic S3 key from the avatar URL
  # GitHub avatar URLs follow the pattern: https://avatars.githubusercontent.com/u/{user_id}?v=4
  # @param url [String] GitHub avatar URL
  # @return [String] S3 key in format "avatars/{user_id}"
  def derive_key(url)
    uri = URI.parse(url)

    # Extract user ID from path: /u/178611968
    match = uri.path.match(%r{\A/u/(\d+)\z})

    unless match
      raise InvalidUrlError, "Cannot extract user ID from URL: #{url}"
    end

    user_id = match[1]
    "avatars/#{user_id}"
  end

  # Downloads avatar image from URL
  # @param url [String] Avatar URL
  # @return [Array<String, String>] [image_data, content_type]
  # @raise [DownloadError] if download fails
  def download_avatar(url)
    uri = URI.parse(url)

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: timeout,
      read_timeout: timeout
    ) do |http|
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "image/*"
      http.request(request)
    end

    handle_response(response: response, url: url)
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
    raise DownloadError, "Network error downloading avatar: #{e.message}"
  end

  # Handles HTTP response from avatar download
  # @param response [Net::HTTPResponse]
  # @param url [String] Original URL for error messages
  # @return [Array<String, String>] [image_data, content_type]
  # @raise [DownloadError] on non-success response
  def handle_response(response:, url:)
    case response
    when Net::HTTPSuccess
      content_type = response["content-type"]&.split(";")&.first || "image/png"
      [ response.body, content_type ]
    when Net::HTTPRedirection
      # Follow redirect (GitHub sometimes redirects avatar URLs)
      new_url = response["location"]
      Rails.logger.info("AvatarDownloadAndUploadService: Following redirect to #{new_url}")
      download_avatar(new_url)
    else
      raise DownloadError, "Failed to download avatar from #{url}: #{response.code} #{response.message}"
    end
  end
end
