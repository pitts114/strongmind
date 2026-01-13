class GithubUserFetcher
  def initialize(gateway: GithubGateway.new)
    @gateway = gateway
  end

  def call(username:)
    Rails.logger.info("Fetching GitHub user: #{username}")

    user_data = gateway.get_user(username: username)
    result = GithubUserSaver.new.call(user_data: user_data)

    Rails.logger.info("Saved GitHub user: #{username} (ID: #{result.id})")
    result
  rescue Github::Client::ClientError => e
    Rails.logger.warn("User fetch failed: #{username} - #{e.message}")
    raise
  end

  private

  attr_reader :gateway
end
