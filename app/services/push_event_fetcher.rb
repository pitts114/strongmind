class PushEventFetcher
  def initialize(gateway: GithubGateway.new)
    @gateway = gateway
  end

  def call
    Rails.logger.info("PushEventFetcher: Fetching public events from GitHub API")

    events = gateway.list_public_events
    push_events = events.select { |event| event["type"] == "PushEvent" }

    Rails.logger.info("PushEventFetcher: Received #{events.length} events, filtered to #{push_events.length} push events")

    push_events
  rescue Github::Client::NotModifiedError
    Rails.logger.info("PushEventFetcher: No new events (304 Not Modified)")
    []
  end

  private

  attr_reader :gateway
end
