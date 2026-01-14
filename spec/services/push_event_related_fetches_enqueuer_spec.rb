require "rails_helper"

RSpec.describe PushEventRelatedFetchesEnqueuer do
  let(:enqueuer) { described_class.new }

  describe "#call" do
    context "when actor is a user" do
      let(:event_data) do
        {
          "actor" => {
            "login" => "octocat",
            "url" => "https://api.github.com/users/octocat"
          },
          "repo" => {
            "name" => "octocat/Hello-World"
          }
        }
      end

      it "enqueues repository fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob)
          .with("octocat", "Hello-World")
      end

      it "enqueues user fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.to have_enqueued_job(FetchAndSaveGithubUserJob)
          .with("octocat")
      end
    end

    context "when actor is a bot" do
      let(:event_data) do
        {
          "actor" => {
            "login" => "github-actions[bot]",
            "url" => "https://api.github.com/users/github-actions[bot]"
          },
          "repo" => {
            "name" => "octocat/Hello-World"
          }
        }
      end

      it "enqueues repository fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob)
      end

      it "does not enqueue user fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.not_to have_enqueued_job(FetchAndSaveGithubUserJob)
      end

      it "logs skipped bot actor" do
        allow(Rails.logger).to receive(:info)

        enqueuer.call(event_data: event_data)

        expect(Rails.logger).to have_received(:info).with(
          "Skipping actor fetch for non-user/non-org actor - " \
          "Actor type: bot, " \
          "Login: github-actions[bot], " \
          "URL: https://api.github.com/users/github-actions[bot]"
        )
      end
    end

    context "when actor is an organization" do
      let(:event_data) do
        {
          "actor" => {
            "login" => "github",
            "url" => "https://api.github.com/orgs/github"
          },
          "repo" => {
            "name" => "github/hub"
          }
        }
      end

      it "enqueues repository fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob)
      end

      it "enqueues organization fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.to have_enqueued_job(FetchAndSaveGithubOrganizationJob)
          .with("github")
      end

      it "does not enqueue user fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.not_to have_enqueued_job(FetchAndSaveGithubUserJob)
      end
    end

    context "when actor type is unknown" do
      let(:event_data) do
        {
          "actor" => {
            "login" => "unknown-actor",
            "url" => "https://api.github.com/something/unknown"
          },
          "repo" => {
            "name" => "owner/repo"
          }
        }
      end

      it "enqueues repository fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob)
      end

      it "does not enqueue user fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.not_to have_enqueued_job(FetchAndSaveGithubUserJob)
      end

      it "does not enqueue organization fetch job" do
        expect {
          enqueuer.call(event_data: event_data)
        }.not_to have_enqueued_job(FetchAndSaveGithubOrganizationJob)
      end

      it "logs skipped unknown actor" do
        allow(Rails.logger).to receive(:info)

        enqueuer.call(event_data: event_data)

        expect(Rails.logger).to have_received(:info).with(
          "Skipping actor fetch for non-user/non-org actor - " \
          "Actor type: unknown, " \
          "Login: unknown-actor, " \
          "URL: https://api.github.com/something/unknown"
        )
      end
    end
  end
end
