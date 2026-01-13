require "rails_helper"

RSpec.describe GithubUser do
  describe "creating a user" do
    it "can create a user with minimal data" do
      user = GithubUser.create!(
        id: 178611968,
        login: "foobar"
      )

      expect(user.id).to eq(178611968)
      expect(user.login).to eq("foobar")
    end

    it "can create a user with full data" do
      user = GithubUser.create!(
        id: 178611968,
        login: "foobar",
        node_id: "U_kgDOCqVnAA",
        avatar_url: "https://avatars.githubusercontent.com/u/178611968?v=4",
        url: "https://api.github.com/users/foobar",
        html_url: "https://github.com/foobar",
        type: "User",
        name: "barbaz",
        company: nil,
        blog: "https://foobar.github.io/portfolio/",
        location: "bizbaz",
        bio: "foo",
        hireable: true,
        public_repos: 9,
        followers: 9,
        following: 12,
        github_created_at: "2024-08-16T20:59:42Z",
        github_updated_at: "2026-01-08T21:33:57Z"
      )

      expect(user.persisted?).to be true
      expect(user.name).to eq("barbaz")
      expect(user.location).to eq("bizbaz")
    end

    it "allows NULL values for optional fields" do
      user = GithubUser.create!(
        id: 999999,
        login: "testuser"
        # All other fields NULL
      )

      expect(user.name).to be_nil
      expect(user.company).to be_nil
      expect(user.bio).to be_nil
    end
  end
end
