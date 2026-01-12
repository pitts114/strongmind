class FetchAndEnqueuePushEventsService
  def call
    events = fetch_events
    enqueue_jobs(events)

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
      SavePushEventJob.perform_later(event)
    end
  end
end
