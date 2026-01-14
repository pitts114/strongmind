# frozen_string_literal: true

require "net/http"
require "uri"
require "tempfile"

class AvatarDownloadAndUploadService
  DEFAULT_TIMEOUT = 30
  DEFAULT_MAX_FILE_SIZE = 10 * 1024 * 1024 # 10 MB

  class Error < StandardError; end
  class DownloadError < Error; end
  class InvalidUrlError < Error; end
  class FileTooLargeError < Error; end

  CONTENT_TYPE_EXTENSIONS = {
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp"
  }.freeze

  def initialize(storage: AvatarStorage::S3.new, timeout: DEFAULT_TIMEOUT, max_file_size: DEFAULT_MAX_FILE_SIZE)
    @storage = storage
    @timeout = timeout
    @max_file_size = max_file_size
  end

  # Downloads an avatar from URL and uploads to S3 storage idempotently
  # @param avatar_url [String] GitHub avatar URL
  # @return [Hash] Result with :key, :uploaded (boolean), and :skipped (boolean)
  # @raise [InvalidUrlError] if URL is invalid or not a GitHub avatar URL
  # @raise [DownloadError] if download fails
  # @raise [FileTooLargeError] if file exceeds max size
  def call(avatar_url:)
    validate_url!(avatar_url)

    key = derive_key(avatar_url)

    if storage.exists?(key: key)
      Rails.logger.info("AvatarDownloadAndUploadService: Avatar already exists, skipping - key: #{key}")
      return { key: key, uploaded: false, skipped: true }
    end

    temp_file = nil
    begin
      Rails.logger.info("AvatarDownloadAndUploadService: Downloading avatar - url: #{avatar_url}")
      temp_file, content_type = download_avatar(avatar_url)

      Rails.logger.info("AvatarDownloadAndUploadService: Uploading avatar - key: #{key}, content_type: #{content_type}")
      storage.upload(key: key, body: temp_file, content_type: content_type)

      Rails.logger.info("AvatarDownloadAndUploadService: Avatar uploaded successfully - key: #{key}")
      { key: key, uploaded: true, skipped: false }
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  attr_reader :storage, :timeout, :max_file_size

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

  # Downloads avatar image from URL to a temp file
  # @param url [String] Avatar URL
  # @return [Array<Tempfile, String>] [temp_file, content_type]
  # @raise [DownloadError] if download fails
  # @raise [FileTooLargeError] if file exceeds max size
  def download_avatar(url)
    uri = URI.parse(url)
    temp_file = Tempfile.new(["avatar", ".tmp"], binmode: true)

    begin
      response = stream_to_tempfile(uri: uri, temp_file: temp_file)
      handle_response(response: response, url: url, temp_file: temp_file)
    rescue => e
      cleanup_temp_file(temp_file)
      raise
    end
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
    raise DownloadError, "Network error downloading avatar: #{e.message}"
  end

  # Streams HTTP response body to a temp file with size checking
  # @param uri [URI] Parsed URI
  # @param temp_file [Tempfile] Target temp file
  # @return [Net::HTTPResponse] The response object
  def stream_to_tempfile(uri:, temp_file:)
    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: timeout,
      read_timeout: timeout
    ) do |http|
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "image/*"

      http.request(request) do |response|
        # Only stream body for successful responses
        if response.is_a?(Net::HTTPSuccess)
          check_content_length_header(response)
          stream_response_body(response: response, temp_file: temp_file)
        end
        return response
      end
    end
  end

  # Checks Content-Length header and raises if too large
  # @param response [Net::HTTPResponse]
  # @raise [FileTooLargeError] if Content-Length exceeds max
  def check_content_length_header(response)
    content_length = response["content-length"]&.to_i
    return unless content_length && content_length > 0

    if content_length > max_file_size
      raise FileTooLargeError,
        "File size #{content_length} bytes exceeds maximum allowed #{max_file_size} bytes"
    end
  end

  # Streams response body to temp file with size tracking
  # @param response [Net::HTTPResponse]
  # @param temp_file [Tempfile]
  # @raise [FileTooLargeError] if streamed bytes exceed max
  def stream_response_body(response:, temp_file:)
    bytes_written = 0

    response.read_body do |chunk|
      bytes_written += chunk.bytesize

      if bytes_written > max_file_size
        raise FileTooLargeError,
          "File size exceeded maximum allowed #{max_file_size} bytes during download"
      end

      temp_file.write(chunk)
    end

    temp_file.rewind
  end

  # Handles HTTP response from avatar download
  # @param response [Net::HTTPResponse]
  # @param url [String] Original URL for error messages
  # @param temp_file [Tempfile] The temp file (only used for success case)
  # @return [Array<Tempfile, String>] [temp_file, content_type]
  # @raise [DownloadError] on non-success response
  def handle_response(response:, url:, temp_file:)
    case response
    when Net::HTTPSuccess
      content_type = response["content-type"]&.split(";")&.first || "image/png"
      [temp_file, content_type]
    when Net::HTTPRedirection
      # Clean up current temp file before following redirect
      cleanup_temp_file(temp_file)

      # Follow redirect (GitHub sometimes redirects avatar URLs)
      new_url = response["location"]
      Rails.logger.info("AvatarDownloadAndUploadService: Following redirect to #{new_url}")
      download_avatar(new_url)
    else
      raise DownloadError, "Failed to download avatar from #{url}: #{response.code} #{response.message}"
    end
  end

  # Safely cleans up a temp file
  # @param temp_file [Tempfile, nil]
  def cleanup_temp_file(temp_file)
    return unless temp_file

    temp_file.close unless temp_file.closed?
    temp_file.unlink if temp_file.path && File.exist?(temp_file.path)
  rescue => e
    Rails.logger.warn("AvatarDownloadAndUploadService: Failed to cleanup temp file: #{e.message}")
  end
end
