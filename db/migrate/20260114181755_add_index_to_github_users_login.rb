class AddIndexToGithubUsersLogin < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :github_users, :login, algorithm: :concurrently
  end
end
