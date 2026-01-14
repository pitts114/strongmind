class GithubGateway
  def initialize
    @client = create_client
  end

  def list_public_events
    client.list_public_events
  end

  def get_user(username:)
    client.get_user(username: username)
  end

  def get_repository(owner:, repo:)
    client.get_repository(owner: owner, repo: repo)
  end

  def get_organization(org:)
    client.get_organization(org: org)
  end

  private

  attr_reader :client

  def create_client
    storage = Storage::Redis.new(redis: REDIS)
    Github::Client.new(storage: storage)
  end
end
