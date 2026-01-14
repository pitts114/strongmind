require "rails_helper"

RSpec.describe "GithubUserFetcher Integration" do
  let(:gateway) { instance_double(GithubGateway) }
  let(:fetcher) { GithubUserFetcher.new(gateway: gateway) }

  describe "fetching and saving a user" do
    let(:user_data) { build(:user_api_response, login: "octocat", user_id: 583231) }

    before do
      allow(gateway).to receive(:get_user)
        .with(username: "octocat")
        .and_return(user_data)
    end

    it "creates a new user record in the database" do
      expect {
        fetcher.call(username: "octocat")
      }.to change(GithubUser, :count).by(1)
    end

    it "persists correct user attributes" do
      result = fetcher.call(username: "octocat")

      expect(result.id).to eq(583231)
      expect(result.login).to eq("octocat")
      expect(result.name).to eq("Test User")
      expect(result.company).to eq("@github")
      expect(result.public_repos).to eq(10)
      expect(result.followers).to eq(100)
    end

    it "returns the saved user" do
      result = fetcher.call(username: "octocat")

      expect(result).to be_a(GithubUser)
      expect(result).to be_persisted
    end
  end

  describe "idempotency - updating existing user" do
    # Inject a fetch guard that always triggers a fetch
    let(:fetch_guard) { instance_double(GithubUserFetchGuard, find_unless_fetch_needed: nil) }
    let(:fetcher) { GithubUserFetcher.new(gateway: gateway, fetch_guard: fetch_guard) }

    let(:initial_data) { build(:user_api_response, login: "octocat", user_id: 583231) }
    let(:updated_data) do
      build(:user_api_response, login: "octocat", user_id: 583231).merge(
        "followers" => 30000,
        "public_repos" => 50
      )
    end

    before do
      allow(gateway).to receive(:get_user)
        .with(username: "octocat")
        .and_return(initial_data, updated_data)
    end

    it "does not create a duplicate user on re-fetch" do
      fetcher.call(username: "octocat")

      expect {
        fetcher.call(username: "octocat")
      }.not_to change(GithubUser, :count)
    end

    it "updates existing user with new data" do
      fetcher.call(username: "octocat")
      fetcher.call(username: "octocat")

      user = GithubUser.find(583231)
      expect(user.followers).to eq(30000)
      expect(user.public_repos).to eq(50)
    end
  end

  describe "fetching multiple different users" do
    let(:user1_data) { build(:user_api_response, login: "user1", user_id: 1001) }
    let(:user2_data) { build(:user_api_response, login: "user2", user_id: 1002) }

    before do
      allow(gateway).to receive(:get_user).with(username: "user1").and_return(user1_data)
      allow(gateway).to receive(:get_user).with(username: "user2").and_return(user2_data)
    end

    it "creates separate user records" do
      expect {
        fetcher.call(username: "user1")
        fetcher.call(username: "user2")
      }.to change(GithubUser, :count).by(2)
    end
  end
end
