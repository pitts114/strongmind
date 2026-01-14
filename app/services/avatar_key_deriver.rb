# frozen_string_literal: true

class AvatarKeyDeriver
  class Error < StandardError; end
  class InvalidUrlError < Error; end

  ALLOWED_HOSTS = /\A(avatars\.)?githubusercontent\.com\z/

  # Derives a deterministic S3 key from a GitHub avatar URL
  # @param url [String] GitHub avatar URL
  # @return [String] S3 key in format "avatars/{user_id}"
  # @raise [InvalidUrlError] if URL is invalid or not a GitHub avatar URL
  def call(url:)
    uri = parse_url(url)
    validate_scheme!(uri, url)
    validate_host!(uri, url)
    extract_key(uri, url)
  end

  private

  def parse_url(url)
    URI.parse(url)
  rescue URI::InvalidURIError => e
    raise InvalidUrlError, "Invalid URL: #{e.message}"
  end

  def validate_scheme!(uri, url)
    return if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    raise InvalidUrlError, "Invalid URL scheme: #{url}"
  end

  def validate_host!(uri, url)
    return if uri.host&.match?(ALLOWED_HOSTS)

    raise InvalidUrlError, "Not a GitHub avatar URL: #{url}"
  end

  def extract_key(uri, url)
    # Extract user ID from path: /u/178611968
    match = uri.path.match(%r{\A/u/(\d+)\z})

    unless match
      raise InvalidUrlError, "Cannot extract user ID from URL: #{url}"
    end

    "avatars/#{match[1]}"
  end
end
