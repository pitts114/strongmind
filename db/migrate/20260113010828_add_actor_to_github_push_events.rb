class AddActorToGithubPushEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :github_push_events, :actor_id, :bigint
  end
end
