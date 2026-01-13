require "rails_helper"

RSpec.describe PushEventDataExtractor do
  describe "#actor" do
    it "returns :user for regular user actors with /users/ URL" do
      event_data = {
        "actor" => {
          "login" => "octocat",
          "url" => "https://api.github.com/users/octocat"
        }
      }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:user)
    end

    it "returns :bot for bot actors with /users/ URL and [bot] suffix" do
      event_data = {
        "actor" => {
          "login" => "github-actions[bot]",
          "url" => "https://api.github.com/users/github-actions[bot]"
        }
      }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:bot)
    end

    it "returns :bot for dependabot with /users/ URL" do
      event_data = {
        "actor" => {
          "login" => "dependabot[bot]",
          "url" => "https://api.github.com/users/dependabot[bot]"
        }
      }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:bot)
    end

    it "returns :unknown for actors with /orgs/ URL" do
      event_data = {
        "actor" => {
          "login" => "github",
          "url" => "https://api.github.com/orgs/github"
        }
      }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:unknown)
    end

    it "returns :unknown for malformed URLs" do
      event_data = {
        "actor" => {
          "login" => "octocat",
          "url" => "https://api.github.com/users/octocat/extra/path"
        }
      }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:unknown)
    end

    it "returns :user for http URLs (not https)" do
      event_data = {
        "actor" => {
          "login" => "octocat",
          "url" => "http://api.github.com/users/octocat"
        }
      }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:user)
    end

    it "returns :user even if actor login is missing (uses URL)" do
      event_data = { "actor" => { "url" => "https://api.github.com/users/octocat" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:user)
    end

    it "returns :bot even if actor login is missing (uses URL)" do
      event_data = { "actor" => { "url" => "https://api.github.com/users/dependabot[bot]" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to eq(:bot)
    end

    it "returns nil if actor URL is missing" do
      event_data = { "actor" => { "login" => "octocat" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor).to be_nil
    end
  end

  describe "#actor_login" do
    it "extracts actor login from event data" do
      event_data = { "actor" => { "login" => "octocat" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor_login).to eq("octocat")
    end

    it "returns nil if actor is missing" do
      event_data = {}
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor_login).to be_nil
    end

    it "returns nil if login is missing" do
      event_data = { "actor" => {} }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor_login).to be_nil
    end
  end

  describe "#actor_url" do
    it "extracts actor URL from event data" do
      event_data = { "actor" => { "url" => "https://api.github.com/users/octocat" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor_url).to eq("https://api.github.com/users/octocat")
    end

    it "returns nil if actor URL is missing" do
      event_data = { "actor" => {} }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.actor_url).to be_nil
    end
  end

  describe "#repository_owner" do
    it "extracts owner from 'owner/repo' format" do
      event_data = { "repo" => { "name" => "octocat/Hello-World" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_owner).to eq("octocat")
    end
  end

  describe "#repository_name" do
    it "extracts repo name from 'owner/repo' format" do
      event_data = { "repo" => { "name" => "octocat/Hello-World" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_name).to eq("Hello-World")
    end
  end
end
