require "rails_helper"

RSpec.describe "PushEventHandler Integration" do
  let(:handler) { PushEventHandler.new }

  describe "processing a user actor event" do
    let(:event_data) { build(:push_event_data, actor_login: "octocat", repo_name: "octocat/hello-world") }

    it "saves the event to the database" do
      expect {
        handler.call(event_data: event_data)
      }.to change(GithubPushEvent, :count).by(1)
    end

    it "enqueues both user and repository fetch jobs" do
      expect {
        handler.call(event_data: event_data)
      }.to have_enqueued_job(FetchAndSaveGithubUserJob).with("octocat")
        .and have_enqueued_job(FetchAndSaveGithubRepositoryJob).with("octocat", "hello-world")
    end

    it "persists correct event attributes" do
      handler.call(event_data: event_data)

      event = GithubPushEvent.find(event_data["id"])
      expect(event.actor_id).to eq(event_data["actor"]["id"])
      expect(event.repository_id).to eq(event_data["repo"]["id"])
      expect(event.ref).to eq("refs/heads/main")
    end

    it "returns the saved push event" do
      result = handler.call(event_data: event_data)

      expect(result).to be_a(GithubPushEvent)
      expect(result.id).to eq(event_data["id"])
    end
  end

  describe "processing a bot actor event" do
    let(:event_data) { build(:push_event_data, :bot_actor, repo_name: "owner/bot-repo") }

    it "saves the event to the database" do
      expect {
        handler.call(event_data: event_data)
      }.to change(GithubPushEvent, :count).by(1)
    end

    it "enqueues repository fetch job" do
      expect {
        handler.call(event_data: event_data)
      }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob).with("owner", "bot-repo")
    end

    it "does not enqueue user fetch job" do
      expect {
        handler.call(event_data: event_data)
      }.not_to have_enqueued_job(FetchAndSaveGithubUserJob)
    end
  end

  describe "processing an org actor event" do
    let(:event_data) { build(:push_event_data, :org_actor, repo_name: "github/docs") }

    it "saves the event to the database" do
      expect {
        handler.call(event_data: event_data)
      }.to change(GithubPushEvent, :count).by(1)
    end

    it "enqueues repository fetch job" do
      expect {
        handler.call(event_data: event_data)
      }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob).with("github", "docs")
    end

    it "does not enqueue user fetch job" do
      expect {
        handler.call(event_data: event_data)
      }.not_to have_enqueued_job(FetchAndSaveGithubUserJob)
    end
  end

  describe "idempotency" do
    let(:event_data) { build(:push_event_data, event_id: "duplicate-test-event") }

    it "does not create duplicate events when called twice" do
      handler.call(event_data: event_data)

      expect {
        handler.call(event_data: event_data)
      }.not_to change(GithubPushEvent, :count)
    end

    it "still enqueues fetch jobs on duplicate event" do
      handler.call(event_data: event_data)

      expect {
        handler.call(event_data: event_data)
      }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob)
        .and have_enqueued_job(FetchAndSaveGithubUserJob)
    end
  end
end
