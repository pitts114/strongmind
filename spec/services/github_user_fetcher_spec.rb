require "rails_helper"

RSpec.describe GithubUserFetcher do
  let(:gateway) { instance_double(GithubGateway) }
  let(:fetcher) { described_class.new(gateway: gateway) }

  describe "#call" do
    context "when user exists" do
      let(:user_data) do
        {
          "id" => 583231,
          "login" => "octocat",
          "node_id" => "MDQ6VXNlcjU4MzIzMQ==",
          "name" => "The Octocat",
          "type" => "User",
          "site_admin" => false
        }
      end

      it "fetches user data and calls GithubUserSaver" do
        saver = instance_double(GithubUserSaver)
        saved_user = instance_double(GithubUser, id: 583231, login: "octocat")

        allow(gateway).to receive(:get_user).with(username: "octocat").and_return(user_data)
        allow(GithubUserSaver).to receive(:new).and_return(saver)
        allow(saver).to receive(:call).with(user_data: user_data).and_return(saved_user)

        result = fetcher.call(username: "octocat")

        expect(gateway).to have_received(:get_user).with(username: "octocat")
        expect(saver).to have_received(:call).with(user_data: user_data)
        expect(result).to eq(saved_user)
      end
    end

    context "when user not found (404)" do
      it "raises Github::Client::ClientError" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::ClientError.new("Not found", status_code: 404, response_body: "")
        )

        expect { fetcher.call(username: "nonexistent") }
          .to raise_error(Github::Client::ClientError)
      end
    end

    context "when rate limited" do
      it "raises Github::Client::RateLimitError" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::RateLimitError.new("Rate limit", status_code: 429, response_body: "")
        )

        expect { fetcher.call(username: "octocat") }
          .to raise_error(Github::Client::RateLimitError)
      end
    end

    context "when server error occurs" do
      it "raises Github::Client::ServerError" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502, response_body: "")
        )

        expect { fetcher.call(username: "octocat") }
          .to raise_error(Github::Client::ServerError)
      end
    end
  end

  describe "error logging" do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
    end

    context "on ServerError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502)
        )

        expect { fetcher.call(username: "octocat") }.to raise_error(Github::Client::ServerError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubUserFetcher: Server error - username: octocat, error: 502 Bad Gateway"
        )
      end
    end

    context "on RateLimitError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::RateLimitError.new("Rate limit exceeded", status_code: 429)
        )

        expect { fetcher.call(username: "octocat") }.to raise_error(Github::Client::RateLimitError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubUserFetcher: Rate limited - username: octocat"
        )
      end
    end

    context "on ClientError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::ClientError.new("Not Found", status_code: 404)
        )

        expect { fetcher.call(username: "octocat") }.to raise_error(Github::Client::ClientError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubUserFetcher: Client error - username: octocat, error: Not Found"
        )
      end
    end
  end
end
