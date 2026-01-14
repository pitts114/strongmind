class GithubRepositoryFetchGuard
  include FetchGuard

  private

  def find_fresh_record(identifier:, threshold:)
    GithubRepository.find_by(full_name: identifier, updated_at: threshold..)
  end
end
