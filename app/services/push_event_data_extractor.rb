class PushEventDataExtractor
  def initialize(event_data:)
    @event_data = event_data
  end

  def actor_login
    event_data.dig("actor", "login")
  end

  def repository_owner
    # "Gabriel-Gerhardt/Webhook-Manager" -> "Gabriel-Gerhardt"
    full_name = event_data.dig("repo", "name")
    full_name&.split("/")&.first
  end

  def repository_name
    # "Gabriel-Gerhardt/Webhook-Manager" -> "Webhook-Manager"
    full_name = event_data.dig("repo", "name")
    full_name&.split("/")&.last
  end

  private

  attr_reader :event_data
end
