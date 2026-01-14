require "rails_helper"

RSpec.describe GithubUserFetchGuard do
  it_behaves_like "a fetch guard",
    model_factory: :github_user,
    identifier_attribute: :login,
    identifier_value: "octocat"
end
