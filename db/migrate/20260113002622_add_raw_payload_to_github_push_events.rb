class AddRawPayloadToGithubPushEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :github_push_events, :raw_payload, :json
  end
end
