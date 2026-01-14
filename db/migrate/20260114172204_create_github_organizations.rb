class CreateGithubOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :github_organizations, id: false do |t|
      # Primary key (GitHub organization ID)
      t.bigint :id, primary_key: true

      # Basic organization info
      t.string :login
      t.string :node_id
      t.string :avatar_url
      t.string :url
      t.string :html_url

      # API URLs
      t.string :repos_url
      t.string :events_url
      t.string :hooks_url
      t.string :issues_url
      t.string :members_url
      t.string :public_members_url

      # Organization type
      t.string :type

      # Profile info (can be NULL)
      t.string :name
      t.string :company
      t.string :blog
      t.string :location
      t.string :email
      t.text :description
      t.string :twitter_username

      # Organization features
      t.boolean :is_verified
      t.boolean :has_organization_projects
      t.boolean :has_repository_projects

      # Stats
      t.integer :public_repos
      t.integer :public_gists
      t.integer :followers
      t.integer :following

      # Timestamps from GitHub
      t.datetime :github_created_at
      t.datetime :github_updated_at
      t.datetime :archived_at

      # Rails timestamps
      t.timestamps
    end
  end
end
