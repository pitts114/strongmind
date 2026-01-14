class GithubUserFetcher
  def initialize(gateway: GithubGateway.new, fetch_guard: GithubUserFetchGuard.new)
    @gateway = gateway
    @fetch_guard = fetch_guard
  end

  def call(username:)
    if (user = fetch_guard.find_unless_fetch_needed(identifier: username))
      Rails.logger.info("Skipping fetch for user #{username} - fetch not needed (last updated: #{user.updated_at})")
      return user
    end

    fetch_and_save(username)
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

  attr_reader :gateway, :fetch_guard

  def fetch_and_save(username)
    Rails.logger.info("Fetching GitHub user: #{username}")

    user_data = gateway.get_user(username: username)
    result = GithubUserSaver.new.call(user_data: user_data)

    Rails.logger.info("Saved GitHub user: #{username} (ID: #{result.id})")
    result
  end
end
