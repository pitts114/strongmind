class AddUserAndRepoToGithubPushEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :github_push_events, :actor_id, :bigint
    add_column :github_push_events, :repo_id, :bigint
  end
end
