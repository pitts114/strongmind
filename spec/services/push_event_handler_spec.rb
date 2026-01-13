require "rails_helper"

RSpec.describe PushEventHandler do
  let(:event_data) do
    {
      "id" => "7401144939",
      "actor" => {
        "id" => 178611968,
        "login" => "Gabriel-Gerhardt"
      },
      "repo" => {
        "id" => 1113957516,
        "name" => "Gabriel-Gerhardt/Webhook-Manager"
      },
      "payload" => {
        "repository_id" => 1113957516,
        "push_id" => 29696227683,
        "ref" => "refs/heads/main"
      }
    }
  end

  describe "#call" do
    it "calls PushEventSaver with event data" do
      saver = instance_double(PushEventSaver)
      push_event = instance_double(GithubPushEvent)
      allow(PushEventSaver).to receive(:new).and_return(saver)
      allow(saver).to receive(:call).with(event_data: event_data).and_return(push_event)

      handler = described_class.new
      result = handler.call(event_data: event_data)

      expect(saver).to have_received(:call).with(event_data: event_data)
      expect(result).to eq(push_event)
    end

    it "enqueues FetchAndSaveGithubUserJob with actor login" do
      allow_any_instance_of(PushEventSaver).to receive(:call).and_return(instance_double(GithubPushEvent))

      expect {
        described_class.new.call(event_data: event_data)
      }.to have_enqueued_job(FetchAndSaveGithubUserJob)
        .with("Gabriel-Gerhardt")
    end

    it "enqueues FetchAndSaveGithubRepositoryJob with owner and repo name" do
      allow_any_instance_of(PushEventSaver).to receive(:call).and_return(instance_double(GithubPushEvent))

      expect {
        described_class.new.call(event_data: event_data)
      }.to have_enqueued_job(FetchAndSaveGithubRepositoryJob)
        .with("Gabriel-Gerhardt", "Webhook-Manager")
    end

    context "when actor login is missing" do
      it "does not enqueue user fetch job" do
        event_data_without_actor = {
          "id" => "7401144939",
          "repo" => { "name" => "Gabriel-Gerhardt/Webhook-Manager" },
          "payload" => { "repository_id" => 1113957516 }
        }
        allow_any_instance_of(PushEventSaver).to receive(:call).and_return(instance_double(GithubPushEvent))

        expect {
          described_class.new.call(event_data: event_data_without_actor)
        }.not_to have_enqueued_job(FetchAndSaveGithubUserJob)
      end
    end

    context "when repo name is missing" do
      it "does not enqueue repository fetch job" do
        event_data_without_repo = {
          "id" => "7401144939",
          "actor" => { "login" => "Gabriel-Gerhardt" },
          "payload" => { "repository_id" => 1113957516 }
        }
        allow_any_instance_of(PushEventSaver).to receive(:call).and_return(instance_double(GithubPushEvent))

        expect {
          described_class.new.call(event_data: event_data_without_repo)
        }.not_to have_enqueued_job(FetchAndSaveGithubRepositoryJob)
      end
    end
  end
end
