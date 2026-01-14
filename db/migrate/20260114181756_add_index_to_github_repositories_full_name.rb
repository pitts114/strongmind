class AddIndexToGithubRepositoriesFullName < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :github_repositories, :full_name, algorithm: :concurrently
  end
end
