require "rails_helper"

RSpec.describe PushEventDataExtractor do
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

  describe "#repository_owner" do
    it "extracts owner from 'owner/repo' format" do
      event_data = { "repo" => { "name" => "octocat/Hello-World" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_owner).to eq("octocat")
    end

    it "returns nil if repo name is missing" do
      event_data = {}
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_owner).to be_nil
    end

    it "returns nil if name is in wrong format" do
      event_data = { "repo" => { "name" => "invalid" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_owner).to eq("invalid")
    end
  end

  describe "#repository_name" do
    it "extracts repo name from 'owner/repo' format" do
      event_data = { "repo" => { "name" => "octocat/Hello-World" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_name).to eq("Hello-World")
    end

    it "returns nil if repo name is missing" do
      event_data = {}
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_name).to be_nil
    end

    it "returns the name if in wrong format" do
      event_data = { "repo" => { "name" => "invalid" } }
      extractor = described_class.new(event_data: event_data)

      expect(extractor.repository_name).to eq("invalid")
    end
  end
end
