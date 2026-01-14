FactoryBot.define do
  factory :github_user do
    sequence(:id) { |n| 100000 + n }
    sequence(:login) { |n| "user-#{n}" }
    name { "Test User" }
    user_type { "User" }
    site_admin { false }
    public_repos { 10 }
    followers { 100 }
    github_created_at { 2.years.ago }
    github_updated_at { 1.day.ago }
  end
end
