# Claude Development Guide for StrongMind GitHub Ingestion

This document provides context and patterns for working on this project.

## Project Overview

This is a GitHub event ingestion system that:
- Fetches public push events from GitHub's API
- Saves push events to the database
- Fetches and stores detailed user (actor) and repository data
- Handles GitHub API rate limiting intelligently
- Processes everything asynchronously with background jobs

**Primary Use Case:** Track GitHub activity by ingesting push events and enriching them with full user and repository details.

---

## Core Architecture Patterns

### 1. Service Objects Pattern

All business logic lives in service classes with a single `call` method:

```ruby
class MyService
  def call(param:)
    # Business logic here
    result
  end
end

# Usage
MyService.new.call(param: value)
```

**Key Services:**
- `FetchAndEnqueuePushEventsService` - Main orchestrator (called by worker)
- `PushEventFetcher` - Fetches events from GitHub API
- `PushEventSaver` - Saves push events to database (find_or_create)
- `PushEventHandler` - Coordinates event saving + job enqueueing
- `PushEventRelatedFetchesEnqueuer` - Decides which fetch jobs to enqueue
- `PushEventDataExtractor` - Extracts actor/repo data from events
- `GithubUserFetcher` - Fetches user data from API
- `GithubUserSaver` - Saves user data to database (find_or_initialize + update)
- `GithubRepositoryFetcher` - Fetches repository data from API
- `GithubRepositorySaver` - Saves repository data to database (find_or_initialize + update)

### 2. Gateway Pattern

`GithubGateway` is the single point of access to the GitHub API client:

```ruby
class GithubGateway
  def list_public_events
    client.list_public_events
  end

  def get_user(username:)
    client.get_user(username: username)
  end

  def get_repository(owner:, repo:)
    client.get_repository(owner: owner, repo: repo)
  end
end
```

**Why?** Centralizes client creation, configuration, and makes testing easier.

### 3. Background Jobs Pattern

All jobs are thin wrappers that delegate to services:

```ruby
class MyJob < ApplicationJob
  retry_on SomeError, wait: :exponentially_longer, attempts: 5
  discard_on PermanentError

  def perform(param)
    MyService.new.call(param: param)
  end
end
```

**Key Jobs:**
- `HandlePushEventJob` - Orchestrates push event processing
- `FetchAndSaveGithubUserJob` - Fetches/saves users in background
- `FetchAndSaveGithubRepositoryJob` - Fetches/saves repos in background

---

## GitHub API Client (`lib/github/client.rb`)

### Error Hierarchy

```
Github::Client::Error (base)
├── NotModifiedError (304)
├── RateLimitError (403 with rate limit headers, 429)
├── ClientError (4xx - user errors)
└── ServerError (5xx - GitHub errors)
```

### Rate Limiting Strategy

The client intelligently distinguishes between rate limit 403s and access denied 403s:

```ruby
# 403 with X-RateLimit-Remaining=0 → RateLimitError
# 403 with retry-after header → RateLimitError
# 403 with "rate limit" in message → RateLimitError
# 403 otherwise → ClientError (access denied)
# 429 → Always RateLimitError
```

**Storage Backends:**
- `Storage::Memory` - In-memory (dev/test)
- `Storage::Redis` - Persistent (production)

### Making Requests

```ruby
# Via Gateway (preferred)
gateway = GithubGateway.new
events = gateway.list_public_events
user = gateway.get_user(username: "octocat")
repo = gateway.get_repository(owner: "octocat", repo: "Hello-World")

# Direct client (avoid - use Gateway)
client = Github::Client.new(storage: storage)
```

---

## Database Models

### GithubPushEvent
- **Primary Key:** `id` (string) - GitHub event ID
- **Key Fields:** `actor_id`, `repository_id`, `push_id`, `ref`, `head`, `before`
- **Raw Data:** `raw` (jsonb) - Full GitHub API response

### GithubUser
- **Primary Key:** `id` (bigint) - GitHub user ID
- **~30 fields** from GitHub REST API (`GET /users/{username}`)
- **Key Fields:** `login`, `name`, `avatar_url`, `public_repos`, `followers`
- **Timestamp Note:** GitHub's `created_at`/`updated_at` are stored as `github_created_at`/`github_updated_at` to avoid conflicts with Rails timestamps

### GithubRepository
- **Primary Key:** `id` (bigint) - GitHub repository ID
- **~80 fields** from GitHub REST API (`GET /repos/{owner}/{repo}`)
- **Key Fields:** `full_name`, `owner_id`, `stargazers_count`, `language`, `topics`
- **License:** Nested license object is flattened with `license_` prefix (`license_key`, `license_name`, `license_spdx_id`, etc.)
- **Timestamp Note:** GitHub's `created_at`/`updated_at` are stored as `github_created_at`/`github_updated_at`; also stores `pushed_at`

**Important:** All use GitHub's IDs as primary keys for idempotency.

---

## Data Flow

```
┌─────────────────────────────────────┐
│ FetchAndEnqueuePushEventsService    │
│ (Called by cron/worker)             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ PushEventFetcher                    │
│ → Calls GithubGateway               │
│ → Returns array of event hashes     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Enqueue HandlePushEventJob          │
│ (one job per event)                 │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ HandlePushEventJob.perform          │
│ → Calls PushEventHandler            │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ PushEventHandler                    │
│ 1. Call PushEventSaver              │
│ 2. Call PushEventRelatedFetchesEnq. │
└──────────────┬──────────────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
┌──────────────┐  ┌──────────────────────────┐
│ PushEventSav.│  │ PushEventRelatedFetches  │
│ → find_or_cr │  │ Enqueuer                 │
│   ate event  │  │ → PushEventDataExtractor │
│              │  │ → Determine actor type   │
│              │  │ → Enqueue repo job       │
│              │  │ → Enqueue user job if    │
│              │  │   actor is :user         │
└──────────────┘  └──────────┬───────────────┘
                             │
                     ┌───────┴───────┐
                     ▼               ▼
          ┌─────────────────┐  ┌─────────────────┐
          │ User Job        │  │ Repository Job  │
          │ → UserFetcher   │  │ → RepoFetcher   │
          │ → UserSaver     │  │ → RepoSaver     │
          └─────────────────┘  └─────────────────┘
```

---

## Actor Type Detection

The system distinguishes between different actor types when processing push events:

### PushEventDataExtractor

```ruby
class PushEventDataExtractor
  def actor
    url = actor_url
    return nil unless url

    # Match pattern: https://api.github.com/users/username
    match = url.match(%r{^https?://[^/]+/users/([^/]+)$})
    return :unknown unless match

    username = match[1]
    username.end_with?("[bot]") ? :bot : :user
  end
end
```

**Actor Types:**
- `:user` - Regular GitHub user (URL matches `/users/{username}` pattern)
- `:bot` - Bot account (URL matches `/users/{username}` pattern with `[bot]` suffix)
- `:unknown` - Organization or unrecognized actor type (e.g., `/orgs/{org}`)
- `nil` - Missing actor URL

**Examples:**
```ruby
# User
{ "url" => "https://api.github.com/users/octocat" } → :user

# Bot
{ "url" => "https://api.github.com/users/github-actions[bot]" } → :bot

# Organization
{ "url" => "https://api.github.com/orgs/github" } → :unknown
```

**Behavior:**
- User fetch jobs are **only enqueued for `:user` actors**
- Bots and unknown actors are **skipped** with info logging
- Repository fetch jobs are **always enqueued** regardless of actor type

---

## Idempotency Guarantees

The system is designed to handle retries, duplicate events, and concurrent operations safely.

### What IS Idempotent ✓

**Database Layer:**
- `PushEventSaver` - Uses `find_or_create_by!(id: ...)` with GitHub event ID
- `GithubUserSaver` - Uses `find_or_initialize_by(id: ...) + update!` pattern
- `GithubRepositorySaver` - Uses `find_or_initialize_by(id: ...) + update!` pattern
- All use GitHub IDs as primary keys - database constraints prevent duplicates

**Multiple executions produce the same final state:**
```ruby
# Safe to call multiple times
GithubUserSaver.new.call(user_data: data)  # First call: creates
GithubUserSaver.new.call(user_data: data)  # Second call: updates with same data
# Result: 1 record with correct data
```

### What ISN'T Idempotent (But That's Acceptable) ✗

**Job Enqueueing:**
- `PushEventRelatedFetchesEnqueuer` - Calling multiple times enqueues duplicate jobs
- `HandlePushEventJob` retries - Each retry re-enqueues fetch jobs
- No job deduplication at the queue level

**Why this is acceptable:**
1. **Data correctness is guaranteed** - Saver services prevent duplicate records
2. **Final state is always correct** - Duplicate jobs update same records safely
3. **Rare occurrence** - Retries/redelivery happen infrequently
4. **Generous API limits** - GitHub allows 5000 requests/hour for authenticated apps
5. **No user-facing impact** - Duplicate work is invisible to users

**Example scenario:**
```
HandlePushEventJob retries due to deadlock:
  → PushEventSaver returns existing event ✓
  → PushEventRelatedFetchesEnqueuer enqueues duplicate fetch jobs ✗
  → 2 FetchAndSaveGithubUserJobs execute
  → Both fetch from API (redundant API calls)
  → Both call GithubUserSaver (idempotent saves)
  → Result: 1 user record, correct data, wasted 1 API call
```

**Trade-off:** System prioritizes **correctness over efficiency** - this is the right choice for data integrity.

---

## Separation of Concerns: Fetcher vs Saver

Services are split into distinct responsibilities following SOLID principles:

### Fetcher Services
**Responsibility:** Make API calls and delegate to savers

```ruby
class GithubUserFetcher
  def call(username:)
    user_data = gateway.get_user(username: username)
    GithubUserSaver.new.call(user_data: user_data)
  end
end
```

### Saver Services
**Responsibility:** Handle persistence and attribute mapping

```ruby
class GithubUserSaver
  def call(user_data:)
    attributes = map_user_attributes(user_data)
    user = GithubUser.find_or_initialize_by(id: attributes[:id])
    user.update!(attributes.except(:id))
    user
  end
end
```

**Benefits:**
- Fetchers can be tested by stubbing gateway
- Savers can be tested with raw data hashes (no API calls)
- Savers are easily reusable (e.g., from webhooks, bulk imports, etc.)
- Clear separation makes code easier to understand and modify

---

## Error Handling Strategy

### Job Retry Configuration

```ruby
# Transient errors - retry with exponential backoff
retry_on Github::Client::ServerError,
  wait: :exponentially_longer,
  attempts: 5

# Rate limits - wait full window
retry_on Github::Client::RateLimitError,
  wait: 1.hour,
  attempts: 3

# Permanent errors - don't retry
discard_on Github::Client::ClientError

# Database errors
retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
```

### Why Separate Jobs for Users vs Repos?

**Different domain concepts with different futures:**
- Users will need profile picture uploads (planned)
- Different monitoring needs (user fetch rate vs repo fetch rate)
- Different failure modes (deleted user vs private repo)
- Independent retry strategies

---

## Testing Patterns

### Service Tests - Use Doubles

```ruby
RSpec.describe MyService do
  let(:gateway) { instance_double(GithubGateway) }
  let(:service) { described_class.new(gateway: gateway) }

  it "does something" do
    allow(gateway).to receive(:get_user).and_return(user_data)

    result = service.call(username: "octocat")

    expect(result).to be_a(GithubUser)
  end
end
```

**No VCR cassettes for new code** - stub gateway/client methods instead for faster tests.

### Job Tests - Verify Delegation

```ruby
RSpec.describe MyJob do
  it "calls the service" do
    service = instance_double(MyService)
    allow(MyService).to receive(:new).and_return(service)
    allow(service).to receive(:call)

    described_class.new.perform("param")

    expect(service).to have_received(:call).with(param: "param")
  end
end
```

### Testing Job Enqueueing

ActiveJob test adapter is configured in `config/environments/test.rb`:

```ruby
config.active_job.queue_adapter = :test
```

Then in tests:

```ruby
expect {
  handler.call(event_data: event_data)
}.to have_enqueued_job(MyJob).with("param")
```

---

## Common Development Tasks

### Adding a New GitHub API Endpoint

1. **Add method to `Github::Client`** (`lib/github/client.rb`):
   ```ruby
   def get_something(id:)
     execute_request(endpoint: "/something/#{id}")
   end
   ```

2. **Add gateway method** (`app/services/github_gateway.rb`):
   ```ruby
   def get_something(id:)
     client.get_something(id: id)
   end
   ```

3. **Add tests** to both files

4. **Create VCR cassettes** for client tests (if needed)

### Adding a New Fetcher/Saver Service Pair

Follow the Fetcher + Saver pattern for separation of concerns:

1. **Create Saver service** (`app/services/github_thing_saver.rb`):
   ```ruby
   class GithubThingSaver
     def call(thing_data:)
       attributes = map_thing_attributes(thing_data)
       thing = GithubThing.find_or_initialize_by(id: attributes[:id])
       thing.update!(attributes.except(:id))
       thing
     end

     private

     def map_thing_attributes(data)
       {
         id: data["id"],
         name: data["name"],
         # ... map all attributes
       }
     end
   end
   ```

2. **Create Fetcher service** (`app/services/github_thing_fetcher.rb`):
   ```ruby
   class GithubThingFetcher
     def initialize(gateway: GithubGateway.new)
       @gateway = gateway
     end

     def call(id:)
       Rails.logger.info("Fetching GitHub thing: #{id}")

       thing_data = gateway.get_thing(id: id)
       result = GithubThingSaver.new.call(thing_data: thing_data)

       Rails.logger.info("Saved GitHub thing: #{id}")
       result
     rescue Github::Client::ClientError => e
       Rails.logger.warn("Thing fetch failed: #{id} - #{e.message}")
       raise
     end

     private

     attr_reader :gateway
   end
   ```

3. **Create job** with appropriate retry strategies

4. **Write tests** - Saver tests use raw data, Fetcher tests stub gateway

### Running Tests

```bash
# All tests
bundle exec rspec

# Specific file
bundle exec rspec spec/services/my_service_spec.rb

# Specific test
bundle exec rspec spec/services/my_service_spec.rb:42
```

---

## Important Gotchas

### 1. Use `find_or_initialize_by` + `update!` Instead of `upsert`

```ruby
# ❌ Don't use upsert - issues with JSON columns
GithubRepository.upsert(attributes, unique_by: :id)

# ✅ Use this pattern instead
repo = GithubRepository.find_or_initialize_by(id: attributes[:id])
repo.update!(attributes.except(:id))
repo
```

**Why?** PostgreSQL has issues comparing JSON columns in upsert's conflict detection.

### 2. Always Use Keyword Arguments

```ruby
# ❌ Bad
def get_user(username)

# ✅ Good
def get_user(username:)
```

**Why?** Consistency with existing codebase and better API clarity.

### 3. Job Class Names Should Be Specific

```ruby
# ❌ Too generic
class ProcessDataJob

# ✅ Specific and clear
class FetchAndSaveGithubUserJob
```

**Why?** Makes monitoring and debugging easier.

### 4. Don't Skip Hooks in Git Commits

```bash
# ❌ Never do this (unless user explicitly requests)
git commit --no-verify

# ✅ Let hooks run
git commit -m "message"
```

### 5. Service Objects Should Be Stateless

```ruby
# ❌ Don't store state in instance variables
class MyService
  def call(data:)
    @data = data  # Don't do this
    process
  end
end

# ✅ Pass data as parameters
class MyService
  def call(data:)
    process(data)
  end

  private

  def process(data)
    # Use local variable
  end
end
```

### 6. Gateway Injection for Testing

Always accept gateway as a parameter for easier testing:

```ruby
class MyService
  def initialize(gateway: GithubGateway.new)
    @gateway = gateway
  end
end
```

---

## Useful Commands

### Redis (Rate Limiting)

```bash
# Connect to Redis
redis-cli -u $REDIS_URL

# Check rate limit info
GET github_api_rate_limit
GET github_api_reset_time
```

### Rails Console Testing

```ruby
# Test event ingestion
service = FetchAndEnqueuePushEventsService.new
result = service.call
# => { events_fetched: 30, jobs_enqueued: 30 }

# Test user fetching
fetcher = GithubUserFetcher.new
user = fetcher.call(username: "octocat")
user.login # => "octocat"

# Test repo fetching
fetcher = GithubRepositoryFetcher.new
repo = fetcher.call(owner: "octocat", repo: "Hello-World")
repo.full_name # => "octocat/Hello-World"

# Check rate limit status
gateway = GithubGateway.new
# The client tracks rate limit internally via Redis
```

---

## Related GitHub Issues

- **#15** - Updated PushEventSaver to store actor_id
- **#16** - Added get_user and get_repository to GitHub client
- **#19** - Created services and jobs for fetching/saving user and repo data
  - Created Fetcher/Saver separation pattern
  - Created PushEventRelatedFetchesEnqueuer for SOLID compliance
  - Implemented actor type detection (user/bot/unknown)
  - Added idempotency analysis

---

## Architecture Decisions

### Why Gateway Pattern?

**Problem:** Services needed to create GitHub client with correct configuration.

**Solution:** Single `GithubGateway` class handles client creation and provides consistent interface.

**Benefits:**
- Centralized configuration
- Easy to mock in tests
- Single point for API access logging
- Can swap client implementations easily

### Why Separate Jobs for Users and Repos?

**Problem:** User and repository fetching seem similar - could use one job.

**Solution:** Separate `FetchAndSaveGithubUserJob` and `FetchAndSaveGithubRepositoryJob`.

**Benefits:**
- Different retry strategies (users vs repos fail differently)
- Independent monitoring and alerting
- Future divergence (user profile pictures, repo webhooks, etc.)
- Clearer job names in background worker UI

### Why Always Fetch Instead of Conditional?

**Problem:** Should we check if data is recent before fetching?

**Solution:** Always fetch from API (for now).

**Benefits:**
- Simpler implementation
- Always have fresh data
- No stale data bugs
- Can add conditional logic later if needed

**Trade-off:** Uses more API quota, but we're far from limits.

### Why Separate Fetcher and Saver Services?

**Problem:** Should fetching and saving be in one service?

**Solution:** Split into `GithubUserFetcher` + `GithubUserSaver` (and same for repos).

**Benefits:**
- **Single Responsibility** - Fetchers handle API, Savers handle persistence
- **Testability** - Savers tested with raw data (no API mocking needed)
- **Reusability** - Savers can be called from webhooks, imports, admin tools
- **SOLID compliance** - Each class has one reason to change

**Example:** If we add bulk import via CSV, we can reuse `GithubUserSaver` without the API-calling logic.

### Why PushEventRelatedFetchesEnqueuer?

**Problem:** `PushEventHandler` had too many responsibilities.

**Solution:** Extract job enqueueing logic to `PushEventRelatedFetchesEnqueuer`.

**Benefits:**
- **PushEventHandler** - Simple coordinator (save, then enqueue)
- **PushEventRelatedFetchesEnqueuer** - Handles job selection and enqueueing
- **Open/Closed Principle** - Add new job types by only modifying enqueuer
- **Easier testing** - Each service has focused tests

---

## Future Enhancements

### Planned (mentioned in issues/conversations):
- [ ] User profile picture fetching and upload to object storage
- [ ] GitHub organization fetching
- [ ] Conditional fetching based on data age

### Potential Improvements:
- [ ] Add webhook support instead of polling
- [ ] GraphQL API for better rate limit usage
- [ ] Bulk upsert for better performance
- [ ] Data retention policies
- [ ] API response caching with ETags

---

## Contact / Questions

For questions about this project, refer to:
- GitHub issues in the repository
- Existing code patterns (services and tests)
- This document

**Last Updated:** January 13, 2026
