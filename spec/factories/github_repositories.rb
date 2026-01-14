FactoryBot.define do
  factory :github_repository do
    sequence(:id) { |n| 200000 + n }
    sequence(:name) { |n| "repo-#{n}" }
    sequence(:full_name) { |n| "owner/repo-#{n}" }
    sequence(:owner_id) { |n| 100000 + n }
    private { false }
    stargazers_count { 0 }
    github_created_at { 2.years.ago }
    github_updated_at { 1.day.ago }
  end
end
