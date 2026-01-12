class CreateGithubPushEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :github_push_events, id: :string do |t|
      t.bigint :repository_id
      t.bigint :push_id
      t.string :ref
      t.string :head
      t.string :before

      t.timestamps
    end
  end
end
