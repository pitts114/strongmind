class PushEventHandler
  def call(event_data:)
    push_event = PushEventSaver.new.call(event_data: event_data)
    PushEventRelatedFetchesEnqueuer.new.call(event_data: event_data)
    push_event
  end
end
