class GithubUserFetchGuard
  include FetchGuard

  private

  def find_fresh_record(identifier:, threshold:)
    GithubUser.find_by(login: identifier, updated_at: threshold..)
  end
end
