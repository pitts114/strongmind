require "rails_helper"

RSpec.describe PushEventSaver do
  let(:saver) { described_class.new }

  describe "#call" do
    describe "logging" do
      before do
        allow(Rails.logger).to receive(:info)
      end

      context "when saving a new event" do
        let(:event_data) do
          {
            "id" => "7401144939",
            "actor" => { "id" => 178611968, "login" => "octocat" },
            "repo" => { "name" => "octocat/hello-world" },
            "payload" => { "repository_id" => 1113957516 }
          }
        end

        it "logs the save with new: true" do
          saver.call(event_data: event_data)

          expect(Rails.logger).to have_received(:info).with(
            "PushEventSaver: Saved event - event_id: 7401144939, actor: octocat, repo: octocat/hello-world, new: true"
          )
        end
      end

      context "when saving an existing event" do
        let(:event_data) do
          {
            "id" => "7401144939",
            "actor" => { "id" => 178611968, "login" => "octocat" },
            "repo" => { "name" => "octocat/hello-world" },
            "payload" => { "repository_id" => 1113957516 }
          }
        end

        before do
          GithubPushEvent.create!(id: "7401144939", repository_id: 999)
        end

        it "logs the save with new: false" do
          saver.call(event_data: event_data)

          expect(Rails.logger).to have_received(:info).with(
            "PushEventSaver: Saved event - event_id: 7401144939, actor: octocat, repo: octocat/hello-world, new: false"
          )
        end
      end
    end

    context "when event data is valid" do
      let(:event_data) do
        {
          "id" => "7401144939",
          "type" => "PushEvent",
          "actor" => {
            "id" => 178611968,
            "login" => "Gabriel-Gerhardt"
          },
          "payload" => {
            "repository_id" => 1113957516,
            "push_id" => 29696227683,
            "ref" => "refs/heads/main",
            "head" => "4b1846dac162ab1ec2631e721be3c40ec74d8f22",
            "before" => "bcccb36af5254b06e9e99e74a4fbf29ab7ed5b2a"
          }
        }
      end

      it "creates a new GithubPushEvent record" do
        expect {
          saver.call(event_data: event_data)
        }.to change(GithubPushEvent, :count).by(1)
      end

      it "maps all fields correctly" do
        result = saver.call(event_data: event_data)

        expect(result.id).to eq("7401144939")
        expect(result.actor_id).to eq(178611968)
        expect(result.repository_id).to eq(1113957516)
        expect(result.push_id).to eq(29696227683)
        expect(result.ref).to eq("refs/heads/main")
        expect(result.head).to eq("4b1846dac162ab1ec2631e721be3c40ec74d8f22")
        expect(result.before).to eq("bcccb36af5254b06e9e99e74a4fbf29ab7ed5b2a")
        expect(result.raw).to eq(event_data)
      end

      it "returns the created record" do
        result = saver.call(event_data: event_data)
        expect(result).to be_a(GithubPushEvent)
        expect(result).to be_persisted
      end
    end

    context "when event with same ID already exists" do
      it "returns existing record without creating duplicate" do
        existing = GithubPushEvent.create!(
          id: "7401144939",
          repository_id: 999,
          push_id: 888
        )

        event_data = {
          "id" => "7401144939",
          "payload" => {
            "repository_id" => 1113957516,
            "push_id" => 29696227683
          }
        }

        expect {
          result = saver.call(event_data: event_data)
          expect(result.id).to eq(existing.id)
          expect(result.repository_id).to eq(999) # Unchanged
        }.not_to change(GithubPushEvent, :count)
      end
    end

    context "when payload is missing" do
      it "creates record with nil values" do
        event_data = { "id" => "7401144939" }

        result = saver.call(event_data: event_data)

        expect(result.id).to eq("7401144939")
        expect(result.repository_id).to be_nil
        expect(result.push_id).to be_nil
      end
    end

    context "when payload fields are missing" do
      it "creates record with available fields" do
        event_data = {
          "id" => "7401144939",
          "payload" => {
            "repository_id" => 1113957516
            # Other fields missing
          }
        }

        result = saver.call(event_data: event_data)

        expect(result.id).to eq("7401144939")
        expect(result.repository_id).to eq(1113957516)
        expect(result.push_id).to be_nil
      end
    end
  end
end
