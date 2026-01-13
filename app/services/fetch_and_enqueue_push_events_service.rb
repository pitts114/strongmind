class FetchAndEnqueuePushEventsService
  def call
    Rails.logger.info("FetchAndEnqueuePushEventsService: Starting fetch cycle")

    events = fetch_events
    Rails.logger.info("FetchAndEnqueuePushEventsService: Fetched #{events.length} push events")

    enqueue_jobs(events)
    Rails.logger.info("FetchAndEnqueuePushEventsService: Enqueued #{events.length} HandlePushEventJob jobs")

    {
      events_fetched: events.length,
      jobs_enqueued: events.length
    }
  end

  private

  def fetch_events
    PushEventFetcher.new.call
  end

  def enqueue_jobs(events)
    events.each do |event|
      HandlePushEventJob.perform_later(event)
    end
  end
end
