require "rails_helper"

RSpec.describe GithubGateway do
  let(:gateway) { described_class.new }
  let(:client) { instance_double(Github::Client) }

  before do
    allow(Github::Client).to receive(:new).and_return(client)
  end

  describe "#list_public_events" do
    context "when client returns events successfully" do
      it "delegates to client and returns the events" do
        events = [
          { "id" => "123", "type" => "PushEvent" },
          { "id" => "456", "type" => "WatchEvent" }
        ]
        allow(client).to receive(:list_public_events).and_return(events)

        result = gateway.list_public_events

        expect(result).to eq(events)
        expect(client).to have_received(:list_public_events)
      end
    end

    context "when client raises NotModifiedError" do
      it "propagates the error" do
        allow(client).to receive(:list_public_events).and_raise(
          Github::Client::NotModifiedError.new("Not modified", status_code: 304)
        )

        expect { gateway.list_public_events }.to raise_error(Github::Client::NotModifiedError)
      end
    end

    context "when client raises RateLimitError" do
      it "propagates the error" do
        allow(client).to receive(:list_public_events).and_raise(
          Github::Client::RateLimitError.new("Rate limit exceeded", status_code: 403)
        )

        expect { gateway.list_public_events }.to raise_error(Github::Client::RateLimitError)
      end
    end

    context "when client raises ServerError" do
      it "propagates the error" do
        allow(client).to receive(:list_public_events).and_raise(
          Github::Client::ServerError.new("Server error", status_code: 500)
        )

        expect { gateway.list_public_events }.to raise_error(Github::Client::ServerError)
      end
    end
  end
end
