require "rails_helper"

RSpec.describe PushEventHandler do
  let(:handler) { described_class.new }
  let(:event_data) do
    {
      "id" => "7401144939",
      "actor" => {
        "id" => 178611968,
        "login" => "Gabriel-Gerhardt",
        "url" => "https://api.github.com/users/Gabriel-Gerhardt"
      },
      "repo" => {
        "id" => 1113957516,
        "name" => "Gabriel-Gerhardt/Webhook-Manager"
      }
    }
  end

  describe "#call" do
    it "calls PushEventSaver with event data" do
      saver = instance_double(PushEventSaver)
      enqueuer = instance_double(PushEventRelatedFetchesEnqueuer)
      push_event = instance_double(GithubPushEvent)

      allow(PushEventSaver).to receive(:new).and_return(saver)
      allow(PushEventRelatedFetchesEnqueuer).to receive(:new).and_return(enqueuer)
      allow(saver).to receive(:call).with(event_data: event_data).and_return(push_event)
      allow(enqueuer).to receive(:call).with(event_data: event_data)

      result = handler.call(event_data: event_data)

      expect(saver).to have_received(:call).with(event_data: event_data)
      expect(result).to eq(push_event)
    end

    it "calls PushEventRelatedFetchesEnqueuer with event data" do
      saver = instance_double(PushEventSaver)
      enqueuer = instance_double(PushEventRelatedFetchesEnqueuer)
      push_event = instance_double(GithubPushEvent)

      allow(PushEventSaver).to receive(:new).and_return(saver)
      allow(PushEventRelatedFetchesEnqueuer).to receive(:new).and_return(enqueuer)
      allow(saver).to receive(:call).and_return(push_event)
      allow(enqueuer).to receive(:call).with(event_data: event_data)

      handler.call(event_data: event_data)

      expect(enqueuer).to have_received(:call).with(event_data: event_data)
    end

    it "returns the saved push event" do
      push_event = instance_double(GithubPushEvent)
      allow_any_instance_of(PushEventSaver).to receive(:call).and_return(push_event)
      allow_any_instance_of(PushEventRelatedFetchesEnqueuer).to receive(:call)

      result = handler.call(event_data: event_data)

      expect(result).to eq(push_event)
    end
  end
end
