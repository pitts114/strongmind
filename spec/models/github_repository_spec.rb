require "rails_helper"

RSpec.describe GithubRepository do
  describe "creating a repository" do
    it "can create a repo with minimal data" do
      repo = GithubRepository.create!(
        id: 1123394671,
        name: "foobar",
        full_name: "foobar/foobar"
      )

      expect(repo.id).to eq(1123394671)
      expect(repo.full_name).to eq("foobar/foobar")
    end

    it "can create a repo with full data including license" do
      repo = GithubRepository.create!(
        id: 1123394671,
        node_id: "R_kgDOQvWkbw",
        name: "foobar",
        full_name: "foobar/foobar",
        private: false,
        owner_id: 106570213,
        html_url: "https://github.com/foobar/foobar",
        description: nil,
        fork: false,
        url: "https://api.github.com/repos/foobar/foobar",
        language: nil,
        stargazers_count: 1,
        watchers_count: 1,
        forks_count: 0,
        open_issues_count: 0,
        default_branch: "main",
        topics: [],
        visibility: "public",
        license_key: "agpl-3.0",
        license_name: "GNU Affero General Public License v3.0",
        license_spdx_id: "AGPL-3.0",
        license_url: "https://api.github.com/licenses/agpl-3.0",
        license_node_id: "MDc6TGljZW5zZTE=",
        github_created_at: "2025-12-26T19:28:30Z",
        github_updated_at: "2026-01-11T21:18:20Z",
        pushed_at: "2026-01-11T21:18:17Z"
      )

      expect(repo.persisted?).to be true
      expect(repo.license_key).to eq("agpl-3.0")
      expect(repo.license_name).to eq("GNU Affero General Public License v3.0")
    end

    it "stores topics as JSON array" do
      repo = GithubRepository.create!(
        id: 999999,
        name: "test-repo",
        full_name: "user/test-repo",
        topics: [ "ruby", "rails", "github-api" ]
      )

      expect(repo.topics).to eq([ "ruby", "rails", "github-api" ])
    end
  end
end
