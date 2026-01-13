require "rails_helper"

RSpec.describe GithubUserSaver do
  let(:saver) { described_class.new }

  describe "#call" do
    let(:user_data) do
      {
        "id" => 583231,
        "login" => "octocat",
        "node_id" => "MDQ6VXNlcjU4MzIzMQ==",
        "name" => "The Octocat",
        "type" => "User",
        "site_admin" => false
      }
    end

    context "when user does not exist" do
      it "creates a new user record" do
        expect {
          saver.call(user_data: user_data)
        }.to change(GithubUser, :count).by(1)

        user = GithubUser.last
        expect(user.id).to eq(583231)
        expect(user.login).to eq("octocat")
        expect(user.name).to eq("The Octocat")
      end
    end

    context "when user already exists" do
      it "updates the existing user record" do
        GithubUser.create!(id: 583231, login: "octocat", name: "Old Name")

        expect {
          saver.call(user_data: user_data)
        }.not_to change(GithubUser, :count)

        user = GithubUser.find(583231)
        expect(user.name).to eq("The Octocat")
      end
    end

    it "maps all user attributes correctly" do
      result = saver.call(user_data: user_data)

      expect(result.id).to eq(583231)
      expect(result.login).to eq("octocat")
      expect(result.node_id).to eq("MDQ6VXNlcjU4MzIzMQ==")
      expect(result.name).to eq("The Octocat")
      expect(result.type).to eq("User")
      expect(result.site_admin).to eq(false)
    end
  end
end
