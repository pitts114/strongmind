require "rails_helper"

RSpec.describe PushEventFetcher do
  let(:fetcher) { described_class.new }
  let(:gateway) { instance_double(GithubGateway) }

  before do
    allow(GithubGateway).to receive(:new).and_return(gateway)
  end

  describe "#call" do
    describe "logging" do
      before do
        allow(Rails.logger).to receive(:info)
      end

      context "when events are fetched successfully" do
        let(:events) do
          [
            { "id" => "1", "type" => "PushEvent" },
            { "id" => "2", "type" => "WatchEvent" },
            { "id" => "3", "type" => "PushEvent" }
          ]
        end

        before do
          allow(gateway).to receive(:list_public_events).and_return(events)
        end

        it "logs the start of the fetch" do
          fetcher.call

          expect(Rails.logger).to have_received(:info).with("PushEventFetcher: Fetching public events from GitHub API")
        end

        it "logs the number of events received and filtered" do
          fetcher.call

          expect(Rails.logger).to have_received(:info).with("PushEventFetcher: Received 3 events, filtered to 2 push events")
        end
      end

      context "when NotModifiedError is raised" do
        before do
          allow(gateway).to receive(:list_public_events).and_raise(
            Github::Client::NotModifiedError.new("Not modified", status_code: 304)
          )
        end

        it "logs that no new events were available" do
          fetcher.call

          expect(Rails.logger).to have_received(:info).with("PushEventFetcher: No new events (304 Not Modified)")
        end
      end
    end

    context "when events are successfully fetched" do
      it "returns only PushEvent events" do
        events = [
          { "id" => "1", "type" => "PushEvent", "repo" => { "id" => 123 } },
          { "id" => "2", "type" => "WatchEvent", "repo" => { "id" => 456 } },
          { "id" => "3", "type" => "PushEvent", "repo" => { "id" => 789 } },
          { "id" => "4", "type" => "IssuesEvent", "repo" => { "id" => 101 } }
        ]
        allow(gateway).to receive(:list_public_events).and_return(events)

        result = fetcher.call

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result).to all(include("type" => "PushEvent"))
        expect(result.map { |e| e["id"] }).to eq([ "1", "3" ])
      end
    end

    context "when no PushEvents are in the response" do
      it "returns an empty array" do
        events = [
          { "id" => "1", "type" => "WatchEvent" },
          { "id" => "2", "type" => "IssuesEvent" }
        ]
        allow(gateway).to receive(:list_public_events).and_return(events)

        result = fetcher.call

        expect(result).to eq([])
      end
    end

    context "when gateway returns empty array" do
      it "returns an empty array" do
        allow(gateway).to receive(:list_public_events).and_return([])

        result = fetcher.call

        expect(result).to eq([])
      end
    end

    context "when gateway raises NotModifiedError (304)" do
      it "returns an empty array" do
        allow(gateway).to receive(:list_public_events).and_raise(
          Github::Client::NotModifiedError.new("Not modified", status_code: 304)
        )

        result = fetcher.call

        expect(result).to eq([])
      end
    end

    context "when gateway raises RateLimitError" do
      it "lets the error bubble up" do
        allow(gateway).to receive(:list_public_events).and_raise(
          Github::Client::RateLimitError.new("Rate limit exceeded", status_code: 403)
        )

        expect { fetcher.call }.to raise_error(Github::Client::RateLimitError)
      end
    end

    context "when gateway raises ServerError" do
      it "lets the error bubble up" do
        allow(gateway).to receive(:list_public_events).and_raise(
          Github::Client::ServerError.new("Server error", status_code: 500)
        )

        expect { fetcher.call }.to raise_error(Github::Client::ServerError)
      end
    end

    context "when gateway raises ClientError" do
      it "lets the error bubble up" do
        allow(gateway).to receive(:list_public_events).and_raise(
          Github::Client::ClientError.new("Client error", status_code: 400)
        )

        expect { fetcher.call }.to raise_error(Github::Client::ClientError)
      end
    end
  end
end
