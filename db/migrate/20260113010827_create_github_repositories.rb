class CreateGithubRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :github_repositories, id: false do |t|
      # Primary key (GitHub repo ID)
      t.bigint :id, primary_key: true

      # Basic repo info
      t.string :node_id
      t.string :name
      t.string :full_name
      t.boolean :private

      # Owner reference (just ID, not full object)
      t.bigint :owner_id

      # URLs
      t.string :html_url
      t.text :description
      t.boolean :fork
      t.string :url
      t.string :forks_url
      t.string :keys_url
      t.string :collaborators_url
      t.string :teams_url
      t.string :hooks_url
      t.string :issue_events_url
      t.string :events_url
      t.string :assignees_url
      t.string :branches_url
      t.string :tags_url
      t.string :blobs_url
      t.string :git_tags_url
      t.string :git_refs_url
      t.string :trees_url
      t.string :statuses_url
      t.string :languages_url
      t.string :stargazers_url
      t.string :contributors_url
      t.string :subscribers_url
      t.string :subscription_url
      t.string :commits_url
      t.string :git_commits_url
      t.string :comments_url
      t.string :issue_comment_url
      t.string :contents_url
      t.string :compare_url
      t.string :merges_url
      t.string :archive_url
      t.string :downloads_url
      t.string :issues_url
      t.string :pulls_url
      t.string :milestones_url
      t.string :notifications_url
      t.string :labels_url
      t.string :releases_url
      t.string :deployments_url

      # Git URLs
      t.string :git_url
      t.string :ssh_url
      t.string :clone_url
      t.string :svn_url

      # Metadata
      t.string :homepage
      t.integer :size
      t.integer :stargazers_count
      t.integer :watchers_count
      t.string :language

      # Features
      t.boolean :has_issues
      t.boolean :has_projects
      t.boolean :has_downloads
      t.boolean :has_wiki
      t.boolean :has_pages
      t.boolean :has_discussions

      # Stats
      t.integer :forks_count
      t.string :mirror_url
      t.boolean :archived
      t.boolean :disabled
      t.integer :open_issues_count

      # License fields (flattened with license_ prefix)
      t.string :license_key
      t.string :license_name
      t.string :license_spdx_id
      t.string :license_url
      t.string :license_node_id

      # Settings
      t.boolean :allow_forking
      t.boolean :is_template
      t.boolean :web_commit_signoff_required

      # Topics (JSON array)
      t.json :topics

      # Visibility
      t.string :visibility

      # More stats
      t.integer :forks
      t.integer :open_issues
      t.integer :watchers
      t.string :default_branch
      t.string :temp_clone_token
      t.integer :network_count
      t.integer :subscribers_count

      # Timestamps from GitHub
      t.datetime :github_created_at
      t.datetime :github_updated_at
      t.datetime :pushed_at

      # Rails timestamps
      t.timestamps
    end
  end
end
