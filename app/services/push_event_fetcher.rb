class PushEventFetcher
  def initialize
    @gateway = GithubGateway.new
  end

  def call
    events = gateway.list_public_events
    events.select { |event| event["type"] == "PushEvent" }
  rescue Github::Client::NotModifiedError
    []
  end

  private

  attr_reader :gateway
end
