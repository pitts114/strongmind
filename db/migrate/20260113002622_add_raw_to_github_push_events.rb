class AddRawToGithubPushEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :github_push_events, :raw, :json
  end
end
