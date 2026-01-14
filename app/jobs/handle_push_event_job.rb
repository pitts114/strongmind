class HandlePushEventJob < ApplicationJob
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3 do |job, error|
    event_id = job.arguments.first&.dig("id")
    Rails.logger.error("HandlePushEventJob: Failed after max retries (deadlock) - event_id: #{event_id}, error: #{error.message}")
  end

  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3 do |job, error|
    event_id = job.arguments.first&.dig("id")
    Rails.logger.error("HandlePushEventJob: Failed after max retries (connection error) - event_id: #{event_id}, error: #{error.message}")
  end

  def perform(event_data)
    PushEventHandler.new.call(event_data: event_data)
  end
end
