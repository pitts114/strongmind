require "rails_helper"

RSpec.describe GithubOrganizationSaver do
  let(:saver) { described_class.new }

  describe "#call" do
    let(:organization_data) do
      {
        "id" => 9919,
        "login" => "github",
        "node_id" => "MDEyOk9yZ2FuaXphdGlvbjk5MTk=",
        "name" => "GitHub",
        "type" => "Organization",
        "description" => "How people build software",
        "is_verified" => true
      }
    end

    context "when organization does not exist" do
      it "creates a new organization record" do
        expect {
          saver.call(organization_data: organization_data)
        }.to change(GithubOrganization, :count).by(1)

        organization = GithubOrganization.last
        expect(organization.id).to eq(9919)
        expect(organization.login).to eq("github")
        expect(organization.name).to eq("GitHub")
      end
    end

    context "when organization already exists" do
      it "updates the existing organization record" do
        GithubOrganization.create!(id: 9919, login: "github", name: "Old Name")

        expect {
          saver.call(organization_data: organization_data)
        }.not_to change(GithubOrganization, :count)

        organization = GithubOrganization.find(9919)
        expect(organization.name).to eq("GitHub")
      end
    end

    it "maps all organization attributes correctly" do
      result = saver.call(organization_data: organization_data)

      expect(result.id).to eq(9919)
      expect(result.login).to eq("github")
      expect(result.node_id).to eq("MDEyOk9yZ2FuaXphdGlvbjk5MTk=")
      expect(result.name).to eq("GitHub")
      expect(result.type).to eq("Organization")
      expect(result.description).to eq("How people build software")
      expect(result.is_verified).to eq(true)
    end
  end
end
