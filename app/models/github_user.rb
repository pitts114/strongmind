class GithubUser < ApplicationRecord
  # Disable single-table inheritance (type column is for GitHub user type)
  self.inheritance_column = nil
end
