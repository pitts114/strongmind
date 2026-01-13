require "rails_helper"

RSpec.describe GithubRepositorySaver do
  let(:saver) { described_class.new }

  describe "#call" do
    let(:repository_data) do
      {
        "id" => 1296269,
        "node_id" => "MDEwOlJlcG9zaXRvcnkxMjk2MjY5",
        "name" => "Hello-World",
        "full_name" => "octocat/Hello-World",
        "owner" => { "id" => 583231 },
        "private" => false,
        "html_url" => "https://github.com/octocat/Hello-World"
      }
    end

    context "when repository does not exist" do
      it "creates a new repository record" do
        expect {
          saver.call(repository_data: repository_data)
        }.to change(GithubRepository, :count).by(1)

        repo = GithubRepository.last
        expect(repo.id).to eq(1296269)
        expect(repo.full_name).to eq("octocat/Hello-World")
        expect(repo.owner_id).to eq(583231)
      end
    end

    context "when repository already exists" do
      it "updates the existing repository record" do
        GithubRepository.create!(id: 1296269, name: "Hello-World", full_name: "octocat/Hello-World", stargazers_count: 100)

        expect {
          saver.call(repository_data: repository_data)
        }.not_to change(GithubRepository, :count)

        repo = GithubRepository.find(1296269)
        expect(repo.full_name).to eq("octocat/Hello-World")
      end
    end

    it "maps all repository attributes correctly" do
      result = saver.call(repository_data: repository_data)

      expect(result.id).to eq(1296269)
      expect(result.node_id).to eq("MDEwOlJlcG9zaXRvcnkxMjk2MjY5")
      expect(result.name).to eq("Hello-World")
      expect(result.full_name).to eq("octocat/Hello-World")
      expect(result.owner_id).to eq(583231)
      expect(result.private).to eq(false)
      expect(result.html_url).to eq("https://github.com/octocat/Hello-World")
    end
  end
end
