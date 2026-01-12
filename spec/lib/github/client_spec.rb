require "spec_helper"
require "webmock/rspec"
require_relative "../../../lib/github/client"

# Configure VCR to match on GitHub-specific headers for these tests
# This ensures we test against the correct API version
VCR.configure do |config|
  config.default_cassette_options = {
    match_requests_on: [
      :method,
      :uri,
      lambda do |r1, r2|
        r1.headers["Accept"] == r2.headers["Accept"] &&
          r1.headers["X-Github-Api-Version"] == r2.headers["X-Github-Api-Version"]
      end
    ],
    record: :once
  }
end

RSpec.describe Github::Client do
  describe "#initialize" do
    it "uses default configuration values" do
      client = described_class.new

      expect(client.base_url).to eq("https://api.github.com")
      expect(client.api_version).to eq("2022-11-28")
      expect(client.timeout).to eq(10)
    end

    it "accepts custom base_url" do
      client = described_class.new(base_url: "https://github.enterprise.com/api/v3")

      expect(client.base_url).to eq("https://github.enterprise.com/api/v3")
    end

    it "accepts custom api_version" do
      client = described_class.new(api_version: "2023-01-01")

      expect(client.api_version).to eq("2023-01-01")
    end

    it "accepts custom timeout" do
      client = described_class.new(timeout: 15)

      expect(client.timeout).to eq(15)
    end
  end

  describe "#list_public_events" do
    let(:client) { described_class.new }

    context "when request is successful" do
      it "returns an array of events" do
        VCR.use_cassette("github/events_success") do
          events = client.list_public_events

          expect(events).to be_an(Array)
          expect(events).not_to be_empty

          # Verify the structure of a GitHub event
          first_event = events.first
          expect(first_event).to have_key("id")
          expect(first_event).to have_key("type")
          expect(first_event).to have_key("actor")
          expect(first_event).to have_key("repo")
        end
      end
    end

    context "when rate limit is exceeded (403)" do
      it "raises RateLimitError" do
        VCR.use_cassette("github/events_rate_limit") do
          expect { client.list_public_events }.to raise_error(Github::Client::RateLimitError) do |error|
            expect(error.message).to eq("GitHub API rate limit exceeded")
            expect(error.status_code).to eq(403)
            expect(error.response_body).to include("rate limit exceeded")
          end
        end
      end
    end

    context "when server error occurs (500)" do
      it "raises ServerError" do
        VCR.use_cassette("github/events_server_error_500") do
          expect { client.list_public_events }.to raise_error(Github::Client::ServerError) do |error|
            expect(error.message).to include("GitHub API server error: 500")
            expect(error.status_code).to eq(500)
          end
        end
      end
    end

    context "when server error occurs (502)" do
      it "raises ServerError" do
        VCR.use_cassette("github/events_server_error_502") do
          expect { client.list_public_events }.to raise_error(Github::Client::ServerError) do |error|
            expect(error.status_code).to eq(502)
          end
        end
      end
    end

    context "when server error occurs (503)" do
      it "raises ServerError" do
        VCR.use_cassette("github/events_server_error_503") do
          expect { client.list_public_events }.to raise_error(Github::Client::ServerError) do |error|
            expect(error.status_code).to eq(503)
          end
        end
      end
    end

    context "when response is not modified (304)" do
      it "raises NotModifiedError" do
        VCR.use_cassette("github/events_not_modified") do
          expect { client.list_public_events }.to raise_error(Github::Client::NotModifiedError) do |error|
            expect(error.message).to eq("Not modified")
            expect(error.status_code).to eq(304)
          end
        end
      end
    end

    context "when client error occurs (404)" do
      it "raises ClientError" do
        VCR.use_cassette("github/events_not_found") do
          expect { client.list_public_events }.to raise_error(Github::Client::ClientError) do |error|
            expect(error.message).to include("GitHub API error: 404")
            expect(error.status_code).to eq(404)
          end
        end
      end
    end

    context "when client error occurs (400)" do
      it "raises ClientError" do
        VCR.use_cassette("github/events_bad_request") do
          expect { client.list_public_events }.to raise_error(Github::Client::ClientError) do |error|
            expect(error.status_code).to eq(400)
          end
        end
      end
    end

    # Network-level errors (not HTTP responses) - use webmock
    context "when network timeout occurs" do
      it "raises ServerError" do
        stub_request(:get, "https://api.github.com/events")
          .to_timeout

        expect { client.list_public_events }.to raise_error(Github::Client::ServerError) do |error|
          expect(error.message).to include("Network error")
          expect(error.status_code).to be_nil
        end
      end
    end

    context "when connection is refused" do
      it "raises ServerError" do
        stub_request(:get, "https://api.github.com/events")
          .to_raise(Errno::ECONNREFUSED)

        expect { client.list_public_events }.to raise_error(Github::Client::ServerError) do |error|
          expect(error.message).to include("Network error")
        end
      end
    end

    context "when invalid JSON is returned" do
      it "raises ServerError" do
        VCR.use_cassette("github/events_invalid_json") do
          expect { client.list_public_events }.to raise_error(Github::Client::ServerError) do |error|
            expect(error.message).to include("Invalid JSON response")
          end
        end
      end
    end

    context "when using custom base_url" do
      it "makes request to custom URL" do
        VCR.use_cassette("github/events_custom_base_url") do
          custom_client = described_class.new(base_url: "https://github.enterprise.com")
          events = custom_client.list_public_events

          expect(events).to be_an(Array)
          expect(events.first["id"]).to eq("123")
        end
      end
    end
  end

  describe "HTTP configuration" do
    it "sends required headers" do
      VCR.use_cassette("github/events_verify_headers") do
        client = described_class.new
        events = client.list_public_events

        expect(events).to be_an(Array)
      end
    end

    it "uses custom api_version in headers" do
      VCR.use_cassette("github/events_custom_api_version") do
        client = described_class.new(api_version: "2023-05-01")
        events = client.list_public_events

        expect(events).to be_an(Array)
      end
    end
  end
end
