require "rails_helper"

RSpec.describe FetchAndEnqueuePushEventsService do
  let(:service) { described_class.new }

  describe "#call" do
    context "when events are fetched" do
      let(:events) do
        [
          {
            "id" => "7401144939",
            "type" => "PushEvent",
            "payload" => { "repository_id" => 1113957516 }
          },
          {
            "id" => "7401144940",
            "type" => "PushEvent",
            "payload" => { "repository_id" => 1113957517 }
          }
        ]
      end

      before do
        allow(service).to receive(:fetch_events).and_return(events)
        allow(HandlePushEventJob).to receive(:perform_later)
      end

      it "enqueues a job for each event" do
        service.call

        expect(HandlePushEventJob).to have_received(:perform_later).twice
        expect(HandlePushEventJob).to have_received(:perform_later).with(events[0])
        expect(HandlePushEventJob).to have_received(:perform_later).with(events[1])
      end

      it "returns metadata about processed events" do
        result = service.call

        expect(result[:events_fetched]).to eq(2)
        expect(result[:jobs_enqueued]).to eq(2)
      end
    end

    context "when no events are fetched" do
      before do
        allow(service).to receive(:fetch_events).and_return([])
      end

      it "does not enqueue any jobs" do
        expect(HandlePushEventJob).not_to receive(:perform_later)

        service.call
      end

      it "returns zero counts" do
        result = service.call

        expect(result[:events_fetched]).to eq(0)
        expect(result[:jobs_enqueued]).to eq(0)
      end
    end

    context "when fetcher returns empty array (304 NotModified)" do
      before do
        allow(service).to receive(:fetch_events).and_return([])
      end

      it "handles gracefully without errors" do
        expect { service.call }.not_to raise_error
      end

      it "returns metadata with zero counts" do
        result = service.call

        expect(result).to eq(events_fetched: 0, jobs_enqueued: 0)
      end
    end

    context "when fetcher raises an error" do
      before do
        allow(service).to receive(:fetch_events).and_raise(Github::Client::RateLimitError.new("Rate limit exceeded", status_code: 429))
      end

      it "propagates the error to caller" do
        expect { service.call }.to raise_error(Github::Client::RateLimitError)
      end
    end
  end
end
