class GithubRepositoryFetcher
  def initialize(gateway: GithubGateway.new, fetch_guard: FetchGuard.new)
    @gateway = gateway
    @fetch_guard = fetch_guard
  end

  def call(owner:, repo:)
    full_name = "#{owner}/#{repo}"
    existing_repository = GithubRepository.find_by(full_name: full_name)

    unless fetch_guard.should_fetch?(record: existing_repository)
      Rails.logger.info("Skipping fetch for repository #{full_name} - fetch not needed (last updated: #{existing_repository.updated_at})")
      return existing_repository
    end

    fetch_and_save(owner, repo)
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

  attr_reader :gateway, :fetch_guard

  def fetch_and_save(owner, repo)
    Rails.logger.info("Fetching GitHub repository: #{owner}/#{repo}")

    repo_data = gateway.get_repository(owner: owner, repo: repo)
    result = GithubRepositorySaver.new.call(repository_data: repo_data)

    Rails.logger.info("Saved GitHub repository: #{owner}/#{repo} (ID: #{result.id})")
    result
  end
end
