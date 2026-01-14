require "rails_helper"

RSpec.describe "FetchAndEnqueuePushEventsService Integration" do
  let(:gateway) { instance_double(GithubGateway) }

  before do
    allow(GithubGateway).to receive(:new).and_return(gateway)
  end

  describe "with multiple events including user and bot actors" do
    let(:user_event) { build(:push_event_data, event_id: "event-user-1", actor_login: "user1", repo_name: "user1/repo1") }
    let(:bot_event) { build(:push_event_data, :bot_actor, event_id: "event-bot-1", repo_name: "owner/bot-repo") }
    let(:events) { [ user_event, bot_event ] }

    before do
      allow(gateway).to receive(:list_public_events).and_return(events)
    end

    it "enqueues HandlePushEventJob for each event" do
      expect {
        FetchAndEnqueuePushEventsService.new.call
      }.to have_enqueued_job(HandlePushEventJob).exactly(2).times
    end

    it "returns correct counts" do
      result = FetchAndEnqueuePushEventsService.new.call

      expect(result[:events_fetched]).to eq(2)
      expect(result[:jobs_enqueued]).to eq(2)
    end
  end

  describe "with no events" do
    before do
      allow(gateway).to receive(:list_public_events).and_return([])
    end

    it "enqueues no jobs" do
      expect {
        FetchAndEnqueuePushEventsService.new.call
      }.not_to have_enqueued_job(HandlePushEventJob)
    end

    it "returns zero counts" do
      result = FetchAndEnqueuePushEventsService.new.call

      expect(result[:events_fetched]).to eq(0)
      expect(result[:jobs_enqueued]).to eq(0)
    end
  end
end
