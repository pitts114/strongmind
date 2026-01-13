class PushEventHandler
  def call(event_data:)
    event_id = event_data["id"]
    Rails.logger.info("PushEventHandler: Processing event - event_id: #{event_id}")

    push_event = PushEventSaver.new.call(event_data: event_data)
    PushEventRelatedFetchesEnqueuer.new.call(event_data: event_data)

    Rails.logger.info("PushEventHandler: Event processed successfully - event_id: #{event_id}")
    push_event
  end
end
