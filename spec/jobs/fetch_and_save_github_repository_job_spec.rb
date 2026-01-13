require "rails_helper"

RSpec.describe FetchAndSaveGithubRepositoryJob, type: :job do
  describe "#perform" do
    it "calls GithubRepositoryFetcher with owner and repo name" do
      fetcher = instance_double(GithubRepositoryFetcher)
      allow(GithubRepositoryFetcher).to receive(:new).and_return(fetcher)
      allow(fetcher).to receive(:call).with(owner: "octocat", repo: "Hello-World")

      described_class.new.perform("octocat", "Hello-World")

      expect(fetcher).to have_received(:call).with(owner: "octocat", repo: "Hello-World")
    end
  end
end
