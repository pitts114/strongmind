class AddAvatarKeyToGithubUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :github_users, :avatar_key, :string
  end
end
