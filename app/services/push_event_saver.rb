class PushEventSaver
  def call(event_data:)
    GithubPushEvent.find_or_create_by!(id: event_data["id"]) do |event|
      event.repository_id = event_data.dig("payload", "repository_id")
      event.push_id = event_data.dig("payload", "push_id")
      event.ref = event_data.dig("payload", "ref")
      event.head = event_data.dig("payload", "head")
      event.before = event_data.dig("payload", "before")
    end
  end
end
