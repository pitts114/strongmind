class GithubOrganization < ApplicationRecord
  # Disable single-table inheritance (type column is for GitHub organization type)
  self.inheritance_column = nil
end
