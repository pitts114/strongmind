class PushEventDataExtractor
  def initialize(event_data:)
    @event_data = event_data
  end

  def actor
    url = actor_url
    return nil unless url

    # Match pattern: https://api.github.com/users/username
    match = url.match(%r{^https?://[^/]+/users/([^/]+)$})
    return :unknown unless match

    username = match[1]
    username.end_with?("[bot]") ? :bot : :user
  end

  def actor_login
    event_data.dig("actor", "login")
  end

  def actor_url
    event_data.dig("actor", "url")
  end

  def repository_owner
    # "pitts114/strongmind" -> "pitts114"
    full_name = event_data.dig("repo", "name")
    full_name.split("/").first
  end

  def repository_name
    # "pitts114/strongmind" -> "strongmind"
    full_name = event_data.dig("repo", "name")
    full_name.split("/").last
  end

  private

  attr_reader :event_data
end
