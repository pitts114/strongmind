require "rails_helper"

RSpec.describe GithubRepositoryFetcher do
  let(:gateway) { instance_double(GithubGateway) }
  let(:fetch_guard) { instance_double(GithubRepositoryFetchGuard) }
  let(:fetcher) { described_class.new(gateway: gateway, fetch_guard: fetch_guard) }

  describe "#call" do
    context "when fetch is needed" do
      let(:repo_data) do
        {
          "id" => 1296269,
          "node_id" => "MDEwOlJlcG9zaXRvcnkxMjk2MjY5",
          "name" => "Hello-World",
          "full_name" => "octocat/Hello-World",
          "owner" => { "id" => 583231 },
          "private" => false,
          "html_url" => "https://github.com/octocat/Hello-World"
        }
      end

      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).with(identifier: "octocat/Hello-World").and_return(nil)
      end

      it "fetches repository data from API and saves it" do
        saver = instance_double(GithubRepositorySaver)
        saved_repo = instance_double(GithubRepository, id: 1296269, full_name: "octocat/Hello-World")

        allow(gateway).to receive(:get_repository).with(owner: "octocat", repo: "Hello-World").and_return(repo_data)
        allow(GithubRepositorySaver).to receive(:new).and_return(saver)
        allow(saver).to receive(:call).with(repository_data: repo_data).and_return(saved_repo)

        result = fetcher.call(owner: "octocat", repo: "Hello-World")

        expect(gateway).to have_received(:get_repository).with(owner: "octocat", repo: "Hello-World")
        expect(saver).to have_received(:call).with(repository_data: repo_data)
        expect(result).to eq(saved_repo)
      end
    end

    context "when fetch is not needed" do
      let(:existing_repo) { instance_double(GithubRepository, updated_at: 2.minutes.ago) }

      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).with(identifier: "octocat/Hello-World").and_return(existing_repo)
        allow(gateway).to receive(:get_repository)
      end

      it "returns existing repository without calling API" do
        allow(Rails.logger).to receive(:info)

        result = fetcher.call(owner: "octocat", repo: "Hello-World")

        expect(result).to eq(existing_repo)
        expect(gateway).not_to have_received(:get_repository)
        expect(Rails.logger).to have_received(:info).with(
          match(/Skipping fetch for repository octocat\/Hello-World - fetch not needed/)
        )
      end
    end

    context "when repository is private (403)" do
      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
      end

      it "raises Github::Client::ClientError" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ClientError.new("Forbidden", status_code: 403, response_body: "")
        )

        expect { fetcher.call(owner: "octocat", repo: "private-repo") }
          .to raise_error(Github::Client::ClientError)
      end
    end

    context "when repository is deleted (404)" do
      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
      end

      it "raises Github::Client::ClientError" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ClientError.new("Not Found", status_code: 404, response_body: "")
        )

        expect { fetcher.call(owner: "octocat", repo: "deleted-repo") }
          .to raise_error(Github::Client::ClientError)
      end
    end

    context "when server error occurs" do
      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
      end

      it "raises Github::Client::ServerError" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502, response_body: "")
        )

        expect { fetcher.call(owner: "octocat", repo: "Hello-World") }
          .to raise_error(Github::Client::ServerError)
      end
    end

    context "when rate limited" do
      before do
        allow(fetch_guard).to receive(:find_unless_fetch_needed).and_return(nil)
      end

      it "raises Github::Client::RateLimitError" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::RateLimitError.new("Rate limit", status_code: 429, response_body: "")
        )

        expect { fetcher.call(owner: "octocat", repo: "Hello-World") }
          .to raise_error(Github::Client::RateLimitError)
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
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502)
        )

        expect { fetcher.call(owner: "octocat", repo: "Hello-World") }.to raise_error(Github::Client::ServerError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubRepositoryFetcher: Server error - repo: octocat/Hello-World, error: 502 Bad Gateway"
        )
      end
    end

    context "on RateLimitError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::RateLimitError.new("Rate limit exceeded", status_code: 429)
        )

        expect { fetcher.call(owner: "octocat", repo: "Hello-World") }.to raise_error(Github::Client::RateLimitError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubRepositoryFetcher: Rate limited - repo: octocat/Hello-World"
        )
      end
    end

    context "on ClientError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ClientError.new("Not Found", status_code: 404)
        )

        expect { fetcher.call(owner: "octocat", repo: "Hello-World") }.to raise_error(Github::Client::ClientError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubRepositoryFetcher: Client error - repo: octocat/Hello-World, error: Not Found"
        )
      end
    end
  end
end
