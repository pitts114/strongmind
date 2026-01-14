class GithubRepositoryFetcher
  def initialize(gateway: GithubGateway.new)
    @gateway = gateway
  end

  def call(owner:, repo:)
    Rails.logger.info("Fetching GitHub repository: #{owner}/#{repo}")

    repo_data = gateway.get_repository(owner: owner, repo: repo)
    result = GithubRepositorySaver.new.call(repository_data: repo_data)

    Rails.logger.info("Saved GitHub repository: #{owner}/#{repo} (ID: #{result.id})")
    result
  rescue Github::Client::ServerError => e
    Rails.logger.warn("GithubRepositoryFetcher: Server error - repo: #{owner}/#{repo}, error: #{e.message}")
    raise
  rescue Github::Client::RateLimitError => e
    Rails.logger.warn("GithubRepositoryFetcher: Rate limited - repo: #{owner}/#{repo}")
    raise
  rescue Github::Client::ClientError => e
    Rails.logger.warn("GithubRepositoryFetcher: Client error - repo: #{owner}/#{repo}, error: #{e.message}")
    raise
  end

  private

  attr_reader :gateway
end
