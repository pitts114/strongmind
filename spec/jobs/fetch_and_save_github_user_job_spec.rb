require "rails_helper"

RSpec.describe FetchAndSaveGithubUserJob, type: :job do
  describe "#perform" do
    it "calls GithubUserFetcher with username" do
      fetcher = instance_double(GithubUserFetcher)
      allow(GithubUserFetcher).to receive(:new).and_return(fetcher)
      allow(fetcher).to receive(:call).with(username: "octocat")

      described_class.new.perform("octocat")

      expect(fetcher).to have_received(:call).with(username: "octocat")
    end
  end

  describe "failure logging" do
    before do
      allow(Rails.logger).to receive(:error)
    end

    describe "on ServerError after max retries" do
      it "logs when all retries exhausted" do
        fetcher = instance_double(GithubUserFetcher)
        allow(GithubUserFetcher).to receive(:new).and_return(fetcher)
        allow(fetcher).to receive(:call).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502)
        )

        job = described_class.new("octocat")
        job.exception_executions["[Github::Client::ServerError]"] = 5

        job.perform_now

        expect(Rails.logger).to have_received(:error).with(
          "FetchAndSaveGithubUserJob: Failed after max retries (server error) - username: octocat, error: 502 Bad Gateway"
        )
      end
    end

    describe "on RateLimitError after max retries" do
      it "logs when all retries exhausted" do
        fetcher = instance_double(GithubUserFetcher)
        allow(GithubUserFetcher).to receive(:new).and_return(fetcher)
        allow(fetcher).to receive(:call).and_raise(
          Github::Client::RateLimitError.new("Rate limit exceeded", status_code: 429)
        )

        job = described_class.new("octocat")
        job.exception_executions["[Github::Client::RateLimitError]"] = 3

        job.perform_now

        expect(Rails.logger).to have_received(:error).with(
          "FetchAndSaveGithubUserJob: Failed after max retries (rate limit) - username: octocat"
        )
      end
    end

    describe "on ClientError" do
      it "logs when job is discarded" do
        fetcher = instance_double(GithubUserFetcher)
        allow(GithubUserFetcher).to receive(:new).and_return(fetcher)
        allow(fetcher).to receive(:call).and_raise(
          Github::Client::ClientError.new("Not Found", status_code: 404)
        )

        described_class.perform_now("deleted-user")

        expect(Rails.logger).to have_received(:error).with(
          "FetchAndSaveGithubUserJob: Discarded (client error) - username: deleted-user, error: Not Found, status: 404"
        )
      end
    end
  end
end
