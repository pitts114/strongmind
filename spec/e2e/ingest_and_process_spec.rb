require "rails_helper"

RSpec.describe "Ingest and Process E2E" do
  # Expected counts based on recorded VCR cassette:
  # - 25 push events total
  # - 18 user actors (7 are bots or orgs, which don't trigger user fetches)
  # - 25 repositories (one per event)
  let(:expected_events) { 25 }
  let(:expected_users) { 18 }
  let(:expected_repositories) { 25 }

  around do |example|
    VCR.use_cassette(
      "e2e/ingest_and_process",
      record: :once,
      allow_playback_repeats: true
    ) do
      example.run
    end
  end

  after do
    # Clean up uploaded avatars from storage
    storage = AvatarStorage::S3.new
    GithubUser.where.not(avatar_key: nil).find_each do |user|
      storage.delete(key: user.avatar_key)
    end
  end

  describe "single ingest and process cycle" do
    before do
      perform_enqueued_jobs do
        FetchAndEnqueuePushEventsService.new.call
      end
    end

    it "saves all events to the database" do
      expect(GithubPushEvent.count).to eq(expected_events)
    end

    it "saves all repositories to the database" do
      expect(GithubRepository.count).to eq(expected_repositories)
    end

    it "saves only user actors (not bots or orgs) to the database" do
      expect(GithubUser.count).to eq(expected_users)
    end

    it "saves events with correct structure" do
      GithubPushEvent.find_each do |event|
        expect(event.id).to be_present
        expect(event.actor_id).to be_present
        expect(event.repository_id).to be_present
        expect(event.raw).to be_a(Hash)
      end
    end

    it "saves repositories with correct structure" do
      GithubRepository.find_each do |repo|
        expect(repo.id).to be_present
        expect(repo.full_name).to be_present
        expect(repo.name).to be_present
        expect(repo.owner_id).to be_present
      end
    end

    it "saves users with correct structure" do
      GithubUser.find_each do |user|
        expect(user.id).to be_present
        expect(user.login).to be_present
      end
    end

    it "uploads avatars to storage and sets avatar_key on users" do
      storage = AvatarStorage::S3.new

      users_with_avatars = GithubUser.where.not(avatar_key: nil)
      expect(users_with_avatars.count).to eq(expected_users)

      users_with_avatars.find_each do |user|
        expect(user.avatar_key).to match(%r{^avatars/\d+(-\d+)?$})
        expect(storage.exists?(key: user.avatar_key)).to be(true), "Avatar not found in storage for user #{user.login}: #{user.avatar_key}"
      end
    end
  end
end
