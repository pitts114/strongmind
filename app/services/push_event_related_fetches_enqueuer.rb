class PushEventRelatedFetchesEnqueuer
  def call(event_data:)
    extractor = PushEventDataExtractor.new(event_data: event_data)

    enqueue_repository_fetch(extractor)
    enqueue_actor_fetch(extractor)
  end

  private

  def enqueue_repository_fetch(extractor)
    FetchAndSaveGithubRepositoryJob.perform_later(
      extractor.repository_owner,
      extractor.repository_name
    )
  end

  def enqueue_actor_fetch(extractor)
    case extractor.actor
    when :user
      FetchAndSaveGithubUserJob.perform_later(extractor.actor_login)
    when :organization
      FetchAndSaveGithubOrganizationJob.perform_later(extractor.actor_login)
    else
      log_skipped_actor(extractor)
    end
  end

  def log_skipped_actor(extractor)
    Rails.logger.info(
      "Skipping actor fetch for non-user/non-org actor - " \
      "Actor type: #{extractor.actor}, " \
      "Login: #{extractor.actor_login}, " \
      "URL: #{extractor.actor_url}"
    )
  end
end
