FactoryBot.define do
  # Raw push event data (as returned by GitHub API)
  factory :push_event_data, class: Hash do
    skip_create

    transient do
      sequence(:event_id) { |n| "event-#{n}" }
      sequence(:actor_id) { |n| 100000 + n }
      actor_login { "test-user" }
      actor_type { :user } # :user, :bot, or :org
      sequence(:repo_id) { |n| 200000 + n }
      repo_name { "owner/test-repo" }
    end

    initialize_with do
      actor_url = case actor_type
      when :bot then "https://api.github.com/users/#{actor_login}"
      when :org then "https://api.github.com/orgs/#{actor_login}"
      else "https://api.github.com/users/#{actor_login}"
      end

      {
        "id" => event_id,
        "type" => "PushEvent",
        "actor" => {
          "id" => actor_id,
          "login" => actor_login,
          "url" => actor_url
        },
        "repo" => {
          "id" => repo_id,
          "name" => repo_name
        },
        "payload" => {
          "repository_id" => repo_id,
          "push_id" => rand(10000000..99999999),
          "ref" => "refs/heads/main",
          "head" => SecureRandom.hex(20),
          "before" => SecureRandom.hex(20)
        }
      }
    end

    trait :bot_actor do
      actor_login { "github-actions[bot]" }
      actor_type { :bot }
    end

    trait :org_actor do
      actor_login { "github" }
      actor_type { :org }
    end
  end

  # Raw user API response
  factory :user_api_response, class: Hash do
    skip_create

    transient do
      sequence(:user_id) { |n| 100000 + n }
      login { "octocat" }
    end

    initialize_with do
      {
        "id" => user_id,
        "login" => login,
        "node_id" => "MDQ6VXNlcjU4MzIzMQ==",
        "name" => "Test User",
        "company" => "@github",
        "type" => "User",
        "site_admin" => false,
        "public_repos" => 10,
        "followers" => 100,
        "following" => 50,
        "created_at" => "2020-01-01T00:00:00Z",
        "updated_at" => "2025-01-01T00:00:00Z"
      }
    end
  end

  # Raw repository API response
  factory :repository_api_response, class: Hash do
    skip_create

    transient do
      sequence(:repo_id) { |n| 200000 + n }
      full_name { "owner/repo" }
    end

    initialize_with do
      owner, name = full_name.split("/")
      {
        "id" => repo_id,
        "name" => name,
        "full_name" => full_name,
        "private" => false,
        "owner" => { "id" => rand(100000..999999), "login" => owner },
        "description" => "Test repository",
        "stargazers_count" => 0,
        "forks_count" => 0,
        "language" => "Ruby",
        "created_at" => "2020-01-01T00:00:00Z",
        "updated_at" => "2025-01-01T00:00:00Z",
        "pushed_at" => "2025-01-01T00:00:00Z"
      }
    end
  end
end
