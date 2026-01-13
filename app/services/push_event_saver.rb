class PushEventSaver
  def call(event_data:)
    event_id = event_data["id"]
    actor_login = event_data.dig("actor", "login")
    repo_name = event_data.dig("repo", "name")

    push_event = GithubPushEvent.find_or_create_by!(id: event_id) do |event|
      event.actor_id = event_data.dig("actor", "id")
      event.repository_id = event_data.dig("payload", "repository_id")
      event.push_id = event_data.dig("payload", "push_id")
      event.ref = event_data.dig("payload", "ref")
      event.head = event_data.dig("payload", "head")
      event.before = event_data.dig("payload", "before")
      event.raw = event_data
    end

    is_new = push_event.previously_new_record?
    Rails.logger.info("PushEventSaver: Saved event - event_id: #{event_id}, actor: #{actor_login}, repo: #{repo_name}, new: #{is_new}")

    push_event
  end
end
