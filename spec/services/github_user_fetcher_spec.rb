require "rails_helper"

RSpec.describe GithubUserFetcher do
  let(:gateway) { instance_double(GithubGateway) }
  let(:fetch_guard) { instance_double(GithubUserFetchGuard) }
  let(:fetcher) { described_class.new(gateway: gateway, fetch_guard: fetch_guard) }

  describe "#call" do
    context "when fetch is needed" do
      let(:user_data) do
        {
          "id" => 583231,
          "login" => "octocat",
          "node_id" => "MDQ6VXNlcjU4MzIzMQ==",
          "name" => "The Octocat",
          "type" => "User",
          "site_admin" => false,
          "avatar_url" => "https://avatars.githubusercontent.com/u/583231?v=4"
        }
      end

      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).with(identifier: "octocat").and_return(nil)
      end

      it "fetches user data from API and saves it" do
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

      it "enqueues UploadAvatarJob with the avatar URL" do
        saver = instance_double(GithubUserSaver)
        saved_user = instance_double(GithubUser, id: 583231, login: "octocat")

        allow(gateway).to receive(:get_user).with(username: "octocat").and_return(user_data)
        allow(GithubUserSaver).to receive(:new).and_return(saver)
        allow(saver).to receive(:call).with(user_data: user_data).and_return(saved_user)

        expect {
          fetcher.call(username: "octocat")
        }.to have_enqueued_job(UploadAvatarJob).with(583231, "https://avatars.githubusercontent.com/u/583231?v=4")
      end
    end

    context "when user has no avatar_url" do
      let(:user_data) do
        {
          "id" => 583231,
          "login" => "octocat",
          "node_id" => "MDQ6VXNlcjU4MzIzMQ==",
          "name" => "The Octocat",
          "type" => "User",
          "site_admin" => false,
          "avatar_url" => nil
        }
      end

      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).with(identifier: "octocat").and_return(nil)
      end

      it "does not enqueue UploadAvatarJob" do
        saver = instance_double(GithubUserSaver)
        saved_user = instance_double(GithubUser, id: 583231, login: "octocat")

        allow(gateway).to receive(:get_user).with(username: "octocat").and_return(user_data)
        allow(GithubUserSaver).to receive(:new).and_return(saver)
        allow(saver).to receive(:call).with(user_data: user_data).and_return(saved_user)

        expect {
          fetcher.call(username: "octocat")
        }.not_to have_enqueued_job(UploadAvatarJob)
      end
    end

    context "when fetch is not needed" do
      let(:existing_user) { instance_double(GithubUser, updated_at: 2.minutes.ago) }

      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).with(identifier: "octocat").and_return(existing_user)
        allow(gateway).to receive(:get_user)
      end

      it "returns existing user without calling API" do
        allow(Rails.logger).to receive(:info)

        result = fetcher.call(username: "octocat")

        expect(result).to eq(existing_user)
        expect(gateway).not_to have_received(:get_user)
        expect(Rails.logger).to have_received(:info).with(
          match(/Skipping fetch for user octocat - fetch not needed/)
        )
      end
    end

    context "when user not found (404)" do
      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
      end

      it "raises Github::Client::ClientError" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::ClientError.new("Not found", status_code: 404, response_body: "")
        )

        expect { fetcher.call(username: "nonexistent") }
          .to raise_error(Github::Client::ClientError)
      end
    end

    context "when rate limited" do
      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
      end

      it "raises Github::Client::RateLimitError" do
        allow(gateway).to receive(:get_user).and_raise(
          Github::Client::RateLimitError.new("Rate limit", status_code: 429, response_body: "")
        )

        expect { fetcher.call(username: "octocat") }
          .to raise_error(Github::Client::RateLimitError)
      end
    end

    context "when server error occurs" do
      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
      end

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
      allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
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
