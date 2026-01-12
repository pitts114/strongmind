class GithubGateway
  def initialize
    @client = Github::Client.new
  end

  def list_public_events
    client.list_public_events
  end

  private

  attr_reader :client
end
