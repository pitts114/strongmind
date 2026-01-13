class PushEventHandler
  def call(event_data:)
    # Save the push event
    push_event = PushEventSaver.new.call(event_data: event_data)

    # Enqueue jobs to fetch related user and repository data
    enqueue_related_fetches(event_data)

    push_event
  end

  private

  def enqueue_related_fetches(event_data)
    extractor = PushEventDataExtractor.new(event_data: event_data)

    # Enqueue user fetch if actor login is present
    if extractor.actor_login.present?
      FetchAndSaveGithubUserJob.perform_later(extractor.actor_login)
    end

    # Enqueue repo fetch if owner and name are both present
    if extractor.repository_owner.present? && extractor.repository_name.present?
      FetchAndSaveGithubRepositoryJob.perform_later(
        extractor.repository_owner,
        extractor.repository_name
      )
    end
  end
end
