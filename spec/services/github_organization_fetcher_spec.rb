require "rails_helper"

RSpec.describe GithubOrganizationFetcher do
  let(:gateway) { instance_double(GithubGateway) }
  let(:fetcher) { described_class.new(gateway: gateway) }

  describe "#call" do
    context "when organization exists" do
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

      it "fetches organization data and calls GithubOrganizationSaver" do
        saver = instance_double(GithubOrganizationSaver)
        saved_organization = instance_double(GithubOrganization, id: 9919, login: "github")

        allow(gateway).to receive(:get_organization).with(org: "github").and_return(organization_data)
        allow(GithubOrganizationSaver).to receive(:new).and_return(saver)
        allow(saver).to receive(:call).with(organization_data: organization_data).and_return(saved_organization)

        result = fetcher.call(org: "github")

        expect(gateway).to have_received(:get_organization).with(org: "github")
        expect(saver).to have_received(:call).with(organization_data: organization_data)
        expect(result).to eq(saved_organization)
      end
    end

    context "when organization not found (404)" do
      it "raises Github::Client::ClientError" do
        allow(gateway).to receive(:get_organization).and_raise(
          Github::Client::ClientError.new("Not found", status_code: 404, response_body: "")
        )

        expect { fetcher.call(org: "nonexistent") }
          .to raise_error(Github::Client::ClientError)
      end
    end

    context "when rate limited" do
      it "raises Github::Client::RateLimitError" do
        allow(gateway).to receive(:get_organization).and_raise(
          Github::Client::RateLimitError.new("Rate limit", status_code: 429, response_body: "")
        )

        expect { fetcher.call(org: "github") }
          .to raise_error(Github::Client::RateLimitError)
      end
    end

    context "when server error occurs" do
      it "raises Github::Client::ServerError" do
        allow(gateway).to receive(:get_organization).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502, response_body: "")
        )

        expect { fetcher.call(org: "github") }
          .to raise_error(Github::Client::ServerError)
      end
    end
  end

  describe "error logging" do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
    end

    context "on ServerError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_organization).and_raise(
          Github::Client::ServerError.new("502 Bad Gateway", status_code: 502)
        )

        expect { fetcher.call(org: "github") }.to raise_error(Github::Client::ServerError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubOrganizationFetcher: Server error - org: github, error: 502 Bad Gateway"
        )
      end
    end

    context "on RateLimitError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_organization).and_raise(
          Github::Client::RateLimitError.new("Rate limit exceeded", status_code: 429)
        )

        expect { fetcher.call(org: "github") }.to raise_error(Github::Client::RateLimitError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubOrganizationFetcher: Rate limited - org: github"
        )
      end
    end

    context "on ClientError" do
      it "logs the error before re-raising" do
        allow(gateway).to receive(:get_organization).and_raise(
          Github::Client::ClientError.new("Not Found", status_code: 404)
        )

        expect { fetcher.call(org: "github") }.to raise_error(Github::Client::ClientError)

        expect(Rails.logger).to have_received(:warn).with(
          "GithubOrganizationFetcher: Client error - org: github, error: Not Found"
        )
      end
    end
  end
end
