require "rails_helper"

RSpec.describe GithubRepositoryFetchGuard do
  it_behaves_like "a fetch guard",
    model_factory: :github_repository,
    identifier_attribute: :full_name,
    identifier_value: "octocat/Hello-World"
end
