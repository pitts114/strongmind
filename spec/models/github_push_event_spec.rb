require "rails_helper"

RSpec.describe GithubPushEvent, type: :model do
  describe "creation" do
    it "creates a valid record with all attributes" do
      event = GithubPushEvent.create!(
        id: "12345678901",
        repository_id: 789012,
        push_id: 10115855396,
        ref: "refs/heads/main",
        head: "abc123def456abc123def456abc123def456abc123",
        before: "def456abc123def456abc123def456abc123def456"
      )

      expect(event).to be_persisted
      expect(event.id).to eq("12345678901")
      expect(event.repository_id).to eq(789012)
      expect(event.push_id).to eq(10115855396)
      expect(event.ref).to eq("refs/heads/main")
      expect(event.head).to eq("abc123def456abc123def456abc123def456abc123")
      expect(event.before).to eq("def456abc123def456abc123def456abc123def456")
    end
  end
end
