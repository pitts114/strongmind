require "rails_helper"

RSpec.describe GithubRepositoryFetcher do
  let(:gateway) { instance_double(GithubGateway) }
  let(:fetcher) { described_class.new(gateway: gateway) }

  describe "#call" do
    context "when repository exists" do
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

      it "fetches repository data and calls GithubRepositorySaver" do
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

    context "when repository is private (403)" do
      it "raises Github::Client::ClientError" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ClientError.new("Forbidden", status_code: 403, response_body: "")
        )

        expect { fetcher.call(owner: "octocat", repo: "private-repo") }
          .to raise_error(Github::Client::ClientError)
      end
    end

    context "when repository is deleted (404)" do
      it "raises Github::Client::ClientError" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ClientError.new("Not Found", status_code: 404, response_body: "")
        )

        expect { fetcher.call(owner: "octocat", repo: "deleted-repo") }
          .to raise_error(Github::Client::ClientError)
      end
    end

    context "when server error occurs" do
      it "raises Github::Client::ServerError" do
        allow(gateway).to receive(:get_repository).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502, response_body: "")
        )

        expect { fetcher.call(owner: "octocat", repo: "Hello-World") }
          .to raise_error(Github::Client::ServerError)
      end
    end

    context "when rate limited" do
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
