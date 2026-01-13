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
  rescue Github::Client::ClientError => e
    Rails.logger.warn("Repository fetch failed: #{owner}/#{repo} - #{e.message}")
    raise
  end

  private

  attr_reader :gateway
end
