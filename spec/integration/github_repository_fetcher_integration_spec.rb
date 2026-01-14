require "rails_helper"

RSpec.describe "GithubRepositoryFetcher Integration" do
  let(:gateway) { instance_double(GithubGateway) }
  let(:fetcher) { GithubRepositoryFetcher.new(gateway: gateway) }

  describe "fetching and saving a repository" do
    let(:repo_data) { build(:repository_api_response, full_name: "octocat/Hello-World", repo_id: 1296269) }

    before do
      allow(gateway).to receive(:get_repository)
        .with(owner: "octocat", repo: "Hello-World")
        .and_return(repo_data)
    end

    it "creates a new repository record in the database" do
      expect {
        fetcher.call(owner: "octocat", repo: "Hello-World")
      }.to change(GithubRepository, :count).by(1)
    end

    it "persists correct repository attributes" do
      result = fetcher.call(owner: "octocat", repo: "Hello-World")

      expect(result.id).to eq(1296269)
      expect(result.name).to eq("Hello-World")
      expect(result.full_name).to eq("octocat/Hello-World")
      expect(result.private).to be false
      expect(result.language).to eq("Ruby")
    end

    it "returns the saved repository" do
      result = fetcher.call(owner: "octocat", repo: "Hello-World")

      expect(result).to be_a(GithubRepository)
      expect(result).to be_persisted
    end
  end

  describe "idempotency - updating existing repository" do
    # Inject a fetch guard that always triggers a fetch
    let(:fetch_guard) { instance_double(GithubRepositoryFetchGuard, find_unless_fetch_needed: nil) }
    let(:fetcher) { GithubRepositoryFetcher.new(gateway: gateway, fetch_guard: fetch_guard) }

    let(:initial_data) { build(:repository_api_response, full_name: "octocat/Hello-World", repo_id: 1296269) }
    let(:updated_data) do
      build(:repository_api_response, full_name: "octocat/Hello-World", repo_id: 1296269).merge(
        "stargazers_count" => 5000,
        "forks_count" => 1000
      )
    end

    before do
      allow(gateway).to receive(:get_repository)
        .with(owner: "octocat", repo: "Hello-World")
        .and_return(initial_data, updated_data)
    end

    it "does not create a duplicate repository on re-fetch" do
      fetcher.call(owner: "octocat", repo: "Hello-World")

      expect {
        fetcher.call(owner: "octocat", repo: "Hello-World")
      }.not_to change(GithubRepository, :count)
    end

    it "updates existing repository with new data" do
      fetcher.call(owner: "octocat", repo: "Hello-World")
      fetcher.call(owner: "octocat", repo: "Hello-World")

      repo = GithubRepository.find(1296269)
      expect(repo.stargazers_count).to eq(5000)
      expect(repo.forks_count).to eq(1000)
    end
  end

  describe "fetching multiple different repositories" do
    let(:repo1_data) { build(:repository_api_response, full_name: "owner1/repo1", repo_id: 2001) }
    let(:repo2_data) { build(:repository_api_response, full_name: "owner2/repo2", repo_id: 2002) }

    before do
      allow(gateway).to receive(:get_repository).with(owner: "owner1", repo: "repo1").and_return(repo1_data)
      allow(gateway).to receive(:get_repository).with(owner: "owner2", repo: "repo2").and_return(repo2_data)
    end

    it "creates separate repository records" do
      expect {
        fetcher.call(owner: "owner1", repo: "repo1")
        fetcher.call(owner: "owner2", repo: "repo2")
      }.to change(GithubRepository, :count).by(2)
    end
  end
end
