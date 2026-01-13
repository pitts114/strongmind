require "rails_helper"

RSpec.describe FetchAndSaveGithubUserJob, type: :job do
  describe "#perform" do
    it "calls GithubUserFetcher with username" do
      fetcher = instance_double(GithubUserFetcher)
      allow(GithubUserFetcher).to receive(:new).and_return(fetcher)
      allow(fetcher).to receive(:call).with(username: "octocat")

      described_class.new.perform("octocat")

      expect(fetcher).to have_received(:call).with(username: "octocat")
    end
  end
end
