class GithubOrganizationFetcher
  def initialize(gateway: GithubGateway.new)
    @gateway = gateway
  end

  def call(org:)
    Rails.logger.info("Fetching GitHub organization: #{org}")

    organization_data = gateway.get_organization(org: org)
    result = GithubOrganizationSaver.new.call(organization_data: organization_data)

    Rails.logger.info("Saved GitHub organization: #{org} (ID: #{result.id})")
    result
  rescue Github::Client::ServerError => e
    Rails.logger.warn("GithubOrganizationFetcher: Server error - org: #{org}, error: #{e.message}")
    raise
  rescue Github::Client::RateLimitError => e
    Rails.logger.warn("GithubOrganizationFetcher: Rate limited - org: #{org}")
    raise
  rescue Github::Client::ClientError => e
    Rails.logger.warn("GithubOrganizationFetcher: Client error - org: #{org}, error: #{e.message}")
    raise
  end

  private

  attr_reader :gateway
end
