class GithubUserFetcher
  def initialize(gateway: GithubGateway.new)
    @gateway = gateway
  end

  def call(username:)
    Rails.logger.info("Fetching GitHub user: #{username}")

    user_data = gateway.get_user(username: username)
    result = GithubUserSaver.new.call(user_data: user_data)

    Rails.logger.info("Saved GitHub user: #{username} (ID: #{result.id})")

    enqueue_avatar_upload(user_data)

    result
  rescue Github::Client::ServerError => e
    Rails.logger.warn("GithubUserFetcher: Server error - username: #{username}, error: #{e.message}")
    raise
  rescue Github::Client::RateLimitError => e
    Rails.logger.warn("GithubUserFetcher: Rate limited - username: #{username}")
    raise
  rescue Github::Client::ClientError => e
    Rails.logger.warn("GithubUserFetcher: Client error - username: #{username}, error: #{e.message}")
    raise
  end

  private

  attr_reader :gateway

  def enqueue_avatar_upload(user_data)
    avatar_url = user_data["avatar_url"]

    if avatar_url.present?
      UploadAvatarJob.perform_later(avatar_url)
      Rails.logger.info("Enqueued avatar upload for user #{user_data['login']} - url: #{avatar_url}")
    else
      Rails.logger.info("No avatar URL found for user #{user_data['login']}, skipping avatar upload")
    end
  end
end
