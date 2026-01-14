FactoryBot.define do
  factory :github_push_event do
    sequence(:id) { |n| "event-#{n}" }
    sequence(:actor_id) { |n| 100000 + n }
    sequence(:repository_id) { |n| 200000 + n }
    sequence(:push_id) { |n| 300000 + n }
    ref { "refs/heads/main" }
    head { SecureRandom.hex(20) }
    before { SecureRandom.hex(20) }
    raw { {} }
  end
end
