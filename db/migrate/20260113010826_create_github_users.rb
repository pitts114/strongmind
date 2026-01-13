class CreateGithubUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :github_users, id: false do |t|
      # Primary key (GitHub user ID)
      t.bigint :id, primary_key: true

      # Basic user info
      t.string :login
      t.string :node_id
      t.string :avatar_url
      t.string :gravatar_id
      t.string :url
      t.string :html_url

      # API URLs
      t.string :followers_url
      t.string :following_url
      t.string :gists_url
      t.string :starred_url
      t.string :subscriptions_url
      t.string :organizations_url
      t.string :repos_url
      t.string :events_url
      t.string :received_events_url

      # User type and status
      t.string :type
      t.string :user_view_type
      t.boolean :site_admin

      # Profile info (can be NULL)
      t.string :name
      t.string :company
      t.string :blog
      t.string :location
      t.string :email
      t.boolean :hireable
      t.text :bio
      t.string :twitter_username

      # Stats
      t.integer :public_repos
      t.integer :public_gists
      t.integer :followers
      t.integer :following

      # Timestamps from GitHub
      t.datetime :github_created_at
      t.datetime :github_updated_at

      # Rails timestamps
      t.timestamps
    end
  end
end
