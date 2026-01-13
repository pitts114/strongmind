class HandlePushEventJob < ApplicationJob
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3

  def perform(event_data)
    PushEventHandler.new.call(event_data: event_data)
  end
end
