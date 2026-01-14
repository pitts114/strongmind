# frozen_string_literal: true

require "aws-sdk-s3"

module AvatarStorage
  class S3
    DEFAULT_BUCKET = "user-avatars"

    def initialize(
      bucket: ENV.fetch("AVATAR_S3_BUCKET", DEFAULT_BUCKET),
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID", "test"),
      secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", "test"),
      endpoint: ENV.fetch("AWS_ENDPOINT_URL", nil),
      force_path_style: ENV.fetch("AWS_FORCE_PATH_STYLE", "false") == "true"
    )
      @bucket = bucket
      @client = build_client(
        region: region,
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        endpoint: endpoint,
        force_path_style: force_path_style
      )
    end

    def upload(key:, body:, content_type: nil)
      options = { bucket: bucket, key: key, body: body }
      options[:content_type] = content_type if content_type

      client.put_object(options)
      true
    end

    def exists?(key:)
      client.head_object(bucket: bucket, key: key)
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    def delete(key:)
      return false unless exists?(key: key)

      client.delete_object(bucket: bucket, key: key)
      true
    end

    private

    attr_reader :bucket, :client

    def build_client(region:, access_key_id:, secret_access_key:, endpoint:, force_path_style:)
      options = {
        region: region,
        credentials: Aws::Credentials.new(access_key_id, secret_access_key)
      }

      if endpoint.present?
        options[:endpoint] = endpoint
        options[:force_path_style] = force_path_style
      end

      Aws::S3::Client.new(options)
    end
  end
end
