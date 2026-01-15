# Design Brief: GitHub Event Ingestion System

## Problem Understanding

The goal is to build an internal service that provides visibility into GitHub activity for analyzing repository usage and contributor behavior. The system must:

1. **Ingest GitHub Push Events** - Continuously poll GitHub's public events API and store push events durably
2. **Enrich Events** - Fetch detailed actor (user) and repository data from the URLs provided in event payloads
3. **Handle Rate Limits Intelligently** - GitHub's unauthenticated API allows only 60 requests/hour, making this the primary constraint
4. **Run Unattended** - Behave predictably under normal conditions and gracefully handle failures without crash-looping

The key challenge is balancing **data freshness** against **API budget**. With a 60 request/hour limit, every API call must be intentional.

---

## Proposed Architecture

### High-Level Design

```
┌────────────────────────────────────────────────────────────────────┐
│                        IngestionWorker                             │
│  Long-running process that polls GitHub every 60 seconds           │
│  Handles signals (SIGTERM/SIGINT) for graceful shutdown            │
└────────────────────────────────┬───────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│              FetchAndEnqueuePushEventsService                      │
│  1. Fetches public events from GitHub API                          │
│  2. Filters to PushEvents only                                     │
│  3. Enqueues one HandlePushEventJob per event                      │
└────────────────────────────────┬───────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                     HandlePushEventJob                             │
│  Background job that processes each event asynchronously           │
└────────────────────────────────┬───────────────────────────────────┘
                                 │
                                 ▼
              ┌─────────────────────────────────────────┐
              │           PushEventHandler              │
              │  Orchestrates event processing          │
              └───────────────────┬─────────────────────┘
                                  │
           ┌──────────────────────┴─────────────────────┐
           ▼                                            ▼
┌─────────────────────────┐               ┌─────────────────────────┐
│    PushEventSaver       │               │ PushEventRelatedFetches │
│  Persists event to DB   │               │      Enqueuer           │
│  (idempotent)           │               │  Enqueues user & repo   │
└─────────────────────────┘               │  fetch jobs             │
                                          └───────────┬─────────────┘
                                                      │
                           ┌──────────────────────────┴──────────────┐
                           ▼                                         ▼
              ┌─────────────────────────┐           ┌─────────────────────────┐
              │ FetchAndSaveGithubUser  │           │ FetchAndSaveGithubRepo  │
              │         Job             │           │         Job             │
              └───────────┬─────────────┘           └───────────┬─────────────┘
                          │                                     │
                          ▼                                     ▼
              ┌─────────────────────────┐           ┌─────────────────────────┐
              │   GithubUserFetcher     │           │ GithubRepositoryFetcher │
              │  → FetchGuard check     │           │  → FetchGuard check     │
              │  → Skip if data fresh   │           │  → Skip if data fresh   │
              │  → API call if stale    │           │  → API call if stale    │
              └───────────┬─────────────┘           └───────────┬─────────────┘
                          │                                     │
                          ▼                                     ▼
              ┌─────────────────────────┐           ┌─────────────────────────┐
              │   GithubUserSaver       │           │ GithubRepositorySaver   │
              │  → Map API attributes   │           │  → Map API attributes   │
              │  → find_or_initialize   │           │  → find_or_initialize   │
              │  → update! (idempotent) │           │  → update! (idempotent) │
              └───────────┬─────────────┘           └─────────────────────────┘
                          │
                          ▼
              ┌─────────────────────────┐
              │    ProcessAvatarJob     │
              │  Enqueued after user    │
              │  save completes         │
              └───────────┬─────────────┘
                          │
                          ▼
              ┌─────────────────────────┐
              │  ProcessAvatarService   │
              │  Coordinates download   │
              │  and storage            │
              └───────────┬─────────────┘
                          │
                          ▼
              ┌─────────────────────────┐
              │ AvatarDownloadAndStore  │
              │       Service           │
              │  → Derive S3 key        │
              │  → Check if exists      │
              │  → Download to temp     │
              │  → Upload to S3         │
              └───────────┬─────────────┘
                          │
                          ▼
              ┌─────────────────────────┐
              │ UpdateGithubUserAvatar  │
              │      KeyService         │
              │  → Update user record   │
              │    with S3 key          │
              └─────────────────────────┘
```

### Core Architectural Patterns

#### 1. Service Object Pattern
All business logic is encapsulated in single-purpose service classes with a `call` method. This provides:
- **Testability**: Services can be tested in isolation by stubbing dependencies
- **Reusability**: Savers can be called from webhooks, imports, or admin tools
- **Clarity**: Each class has one reason to change (Single Responsibility Principle)

#### 2. Fetcher + Saver Separation
API-calling code is separated from persistence code:
- **Fetcher**: Makes API calls, delegates to Saver
- **Saver**: Handles attribute mapping and database writes

This separation means Savers can be tested with raw data hashes without mocking HTTP.

#### 3. Gateway Pattern
`GithubGateway` is the single point of access to the GitHub API, centralizing client configuration and making it easy to mock in tests.

#### 4. Fetch Guard Pattern
Before making an API call, fetchers check with `FetchGuard` whether a fetch is needed:
- If data exists and is fresh (< 5 minutes old), skip the API call
- If data is stale or missing, proceed with fetch

This dramatically reduces API calls when processing duplicate or related events.

---

## Data Modeling Decisions

### Schema Overview

The system uses three primary tables:

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `github_push_events` | `id` (string) | Store push events with GitHub's event ID |
| `github_users` | `id` (bigint) | Store enriched user/actor data |
| `github_repositories` | `id` (bigint) | Store enriched repository data |

### Decision 1: GitHub IDs as Primary Keys

**Choice**: Use GitHub's IDs as our primary keys rather than generating our own.

**Why**:
- **Natural idempotency** - Inserting the same event twice is automatically a no-op (primary key conflict)
- **No mapping table needed** - We don't need to track "our ID → GitHub ID" relationships
- **Simpler queries** - Foreign keys in events directly reference users/repos without joins
- **Referential integrity** - `github_push_events.actor_id` can directly reference `github_users.id`

**Trade-off**: We're coupling our schema to GitHub's ID scheme. If GitHub ever changed their ID format (unlikely), we'd need a migration.

### Decision 2: Extracted Fields for Queryability

**Choice**: Extract key push event fields into dedicated columns while preserving the payload.

**Extracted fields from push events** (queryable without JSON parsing):
- `repository_id` - Repository identifier for filtering and joins
- `actor_id` - Actor identifier for filtering and joins
- `push_id` - Unique push identifier
- `ref` - Git ref that was pushed (e.g., `refs/heads/main`)
- `head` - SHA of the head commit after the push
- `before` - SHA of the head commit before the push

**Why**: SQL queries on native columns are faster and more ergonomic than JSON path queries. The `raw` column preserves the push event's `payload` object for audit and debugging purposes.

### Decision 3: Timestamp Column Naming

**Choice**: Rename GitHub's `created_at`/`updated_at` to `github_created_at`/`github_updated_at`.

**Why**: Rails automatically manages `created_at` and `updated_at` columns for record lifecycle tracking. GitHub's timestamps represent when the user/repo was created on GitHub, not when our record was created. Using distinct names avoids confusion and prevents Rails from overwriting GitHub's values.

```ruby
# In saver services:
{
  github_created_at: data["created_at"],  # When GitHub account was created
  github_updated_at: data["updated_at"],  # When GitHub account was last modified
  # Rails manages created_at/updated_at automatically for our records
}
```

### Decision 4: Flattened License Structure

**Choice**: Flatten the nested `license` object in repositories into prefixed columns.

GitHub returns:
```json
{
  "license": {
    "key": "mit",
    "name": "MIT License",
    "spdx_id": "MIT",
    "url": "https://api.github.com/licenses/mit"
  }
}
```

We store as:
```
license_key: "mit"
license_name: "MIT License"
license_spdx_id: "MIT"
license_url: "https://api.github.com/licenses/mit"
```

**Why**: Avoids nested JSON queries for common license lookups. Easy to query "all MIT-licensed repos" with a simple `WHERE license_key = 'mit'`.

### Decision 5: Strategic Indexing

**Indexes added**:
- `github_users.login` - Fast lookups for staleness checks (FetchGuard queries by username)
- `github_repositories.full_name` - Fast lookups for staleness checks (FetchGuard queries by "owner/repo")
- Primary key indexes on all `id` columns (automatic)

**Why these fields**: The FetchGuard pattern requires fast lookups by the identifier we receive from GitHub (username or full_name), not by our primary key. Without these indexes, every fetch job would do a full table scan.

**Indexes not added**:
- `github_push_events.actor_id`
- `github_push_events.repository_id`

**Why not**: The application's role is to ingest and store data—it doesn't perform joins between push events, users, and repositories. Future analytics queries might benefit from these indexes, but adding indexes has a write-time cost. Since we're optimizing for ingestion throughput and the application itself doesn't query by these foreign keys, we defer index creation until a concrete query need arises.

---

## Key Tradeoffs and Assumptions

### Tradeoff: Fetch Guards Use Database Staleness, Not In-Flight Tracking

**Decision**: The `FetchGuard` determines whether to fetch by checking if a database record exists and how recently it was updated. It does not track whether another job is currently fetching the same resource.

**Current behavior**:
```
Job A starts: FetchGuard checks DB → no record exists → proceeds with API call
Job B starts: FetchGuard checks DB → no record exists → proceeds with API call
Job A completes: saves user to DB
Job B completes: saves same user to DB (redundant but harmless)
```

Both jobs make API calls because neither knows the other is in-flight.

**Why this is acceptable**:
1. **Rare occurrence** - The race window is milliseconds; both jobs must start before either completes
2. **Data correctness guaranteed** - The idempotent saver pattern ensures the final database state is correct regardless of how many jobs write
3. **Simplicity** - No additional infrastructure or failure modes to manage

**How it could be improved with Redis**:

A more sophisticated approach would track in-flight fetches using Redis atomic operations:

```ruby
# Pseudocode for enhanced FetchGuard
def should_fetch?(resource_key:)
  # Try to acquire a lock with automatic expiration
  lock_acquired = redis.set("fetch:#{resource_key}", job_id, nx: true, ex: 30)

  if lock_acquired
    true  # We own the fetch, proceed
  else
    false # Another job is fetching, skip
  end
end

def release_lock(resource_key:)
  redis.del("fetch:#{resource_key}")
end
```

This would eliminate redundant API calls by ensuring only one job fetches a given user or repository at a time. Jobs that lose the race would either:
- Skip entirely (if data will be fresh soon anyway)
- Wait and retry after a short delay
- Proceed without fetching (use whatever data exists after the winner completes)

**Why we didn't implement this**:
1. **Added complexity** - Redis locks introduce edge cases (orphaned locks, TTL tuning, connection failures)
2. **Marginal benefit** - With a 5-minute staleness window, most duplicate fetches are already prevented
3. **API budget is sufficient** - At 60 requests/hour unauthenticated (or 5,000 authenticated), occasional duplicates don't exhaust the budget
4. **Correctness is preserved** - The current approach never produces incorrect data, just occasional extra work

The `FetchGuard` abstraction makes this enhancement straightforward to add later if metrics show the race condition is causing API budget problems.

---

## Rate Limiting Strategy

### The Challenge

GitHub's unauthenticated API allows **60 requests per hour**. With the system making:
- 1 request per poll cycle (events list)
- 1 request per unique user (enrichment)
- 1 request per unique repository (enrichment)

A naive implementation would exhaust the budget within minutes.

### Solution: Multi-Layer Defense

#### Layer 1: Proactive Rate Limiter
The `Github::RateLimiter` class checks limits **before** making requests:
```ruby
# Pseudocode
if remaining_requests == 0
  sleep_time = reset_time - now + 5_second_buffer
  sleep(sleep_time)
end
```

This prevents wasted requests that would just get 429 responses.

#### Layer 2: Fetch Guards (Staleness Checking)
Before each user/repo fetch, `FetchGuard` checks:
1. Does this record exist in our database?
2. Was it updated within the staleness threshold (default: 5 minutes)?

If both are true, skip the API call entirely. This is the biggest API saver—popular users appearing in many events are only fetched once per threshold period.

#### Layer 3: Exponential Backoff on Errors
Jobs that hit rate limits retry with long waits:
```ruby
retry_on Github::Client::RateLimitError, wait: 1.hour, attempts: 3
```

This spreads retry load across the next rate limit window.

#### Layer 4: Ingestion Worker Backoff
The main polling loop backs off on rate limit errors:
```ruby
RATE_LIMIT_BACKOFF = 300  # 5 minutes
```

This prevents the events-list poll from burning budget when limits are hit.

### Shared State via Redis

The application runs as multiple processes:
- **IngestionWorker** - Long-running process that polls for events
- **Sidekiq workers** - Multiple background job processors fetching users/repos
- **Web process** - Rails server (if running)

All of these processes share a single GitHub API rate limit (60 requests/hour). Without coordination, each process would track its own view of the rate limit, leading to:
- Process A thinks 30 requests remain
- Process B thinks 30 requests remain
- Together they make 60 requests, exhausting the budget
- Both then hit 429 errors unexpectedly

**Solution: Pluggable Storage Abstraction**

The `Github::Client` library is designed to be storage-agnostic. It depends on an abstract `Github::Storage::Interface` that defines three simple operations:

```ruby
# lib/github/storage.rb
class Github::Storage::Interface
  def get(key)    # Retrieve a value
  def set(key, value, ttl:)  # Store a value with optional expiration
  def delete(key) # Remove a value
end
```

The library ships with an in-memory implementation (`Github::Storage::Memory`) suitable for single-process development and testing. For production multi-process deployments, the application provides a Redis implementation:

```ruby
# lib/storage/redis.rb
class Storage::Redis < Github::Storage::Interface
  def initialize(redis:)
    @redis = redis
  end

  def get(key)
    redis.get(key)
  end

  def set(key, value, ttl: nil)
    ttl ? redis.setex(key, ttl, value) : redis.set(key, value)
  end

  def delete(key)
    redis.del(key)
  end
end
```

The `GithubGateway` wires everything together, injecting the Redis storage into the client:

```ruby
# app/services/github_gateway.rb
class GithubGateway
  def create_client
    storage = Storage::Redis.new(redis: REDIS)  # Shared Redis connection
    Github::Client.new(storage: storage)
  end
end
```

**How rate limit tracking works across processes:**

1. **After each API response**, the `RateLimiter` extracts GitHub's rate limit headers and stores them:
   ```ruby
   # Headers: X-RateLimit-Remaining: 45, X-RateLimit-Reset: 1705234567
   storage.set("github:rate_limit:core", { remaining: 45, reset: 1705234567 }.to_json, ttl: 3600)
   ```

2. **Before each API request**, the `RateLimiter` checks the shared state:
   ```ruby
   data = JSON.parse(storage.get("github:rate_limit:core"))
   if data["remaining"] == 0
     sleep_duration = data["reset"] - Time.now.to_i + 5  # 5-second buffer
     sleep(sleep_duration)
   end
   ```

3. **After reset**, the stored data is cleared so fresh headers are recorded on the next request.

This gives all processes a consistent, real-time view of the API budget. When one process sees the `X-RateLimit-Remaining` header drop to 10, all other processes immediately know to be cautious. When the limit is exhausted, all processes sleep until the reset time rather than racing to burn the remaining budget.

### Rate Limit Behavior Summary

| Scenario | Behavior |
|----------|----------|
| Normal operation | Poll every 60s, enrich via background jobs |
| Rate limit imminent | RateLimiter sleeps until reset |
| Rate limit exceeded (429) | Jobs retry after 1 hour |
| Fresh data exists | FetchGuard skips API call |

---

## Durability & Restart Safety

### Database-Level Durability

All data is persisted to PostgreSQL using idempotent patterns:

| Model | Pattern | Idempotency |
|-------|---------|-------------|
| GithubPushEvent | `find_or_create_by!(id:)` | Event ID is unique; re-insert is no-op |
| GithubUser | `find_or_initialize_by(id:) + update!` | Re-fetch updates existing record |
| GithubRepository | `find_or_initialize_by(id:) + update!` | Re-fetch updates existing record |

### Job-Level Durability

Background jobs use Sidekiq with Redis persistence:
- Jobs survive process restarts
- Failed jobs retry with exponential backoff
- Permanent failures are discarded with logging

### Raw Payload Preservation

The push event's `payload` object is stored in `github_push_events.raw` (JSON column). This includes commit details, push size, and other push-specific data not extracted into columns. This enables:
- Debugging without re-fetching from GitHub
- Future analysis of fields not currently extracted (e.g., individual commits)
- Audit trail of the push payload data

**Why JSON instead of JSONB?** PostgreSQL's `json` type stores the exact text representation of the JSON, while `jsonb` stores a decomposed binary format. The key difference for audit purposes: `json` preserves duplicate keys and key ordering, while `jsonb` silently discards duplicates (keeping only the last value) and doesn't guarantee key order. Since the `raw` column exists specifically to preserve the original API response exactly as received, `json` is the appropriate choice—if GitHub ever sends malformed JSON with duplicate keys, we want to see that anomaly rather than have it silently normalized away.

### Restart Safety

If the system restarts mid-operation:
1. **In-progress jobs**: Retried by Sidekiq from persisted state
2. **Pending events**: Re-fetched on next poll (deduplicated by event ID)
3. **Partial enrichment**: User/repo jobs complete independently

No special recovery logic needed—the idempotent design handles restarts naturally.

---

## Testing Strategy

### Philosophy: Test All Behavior

Every piece of business logic is unit tested. The goal is comprehensive coverage—if behavior exists, it should have a test. This ensures confidence when refactoring and serves as documentation for how each component is expected to work.

### Test Pyramid

#### Unit Tests (Foundation)
The bulk of the test suite consists of unit tests for:
- **Services** - Each service class has its own spec testing all code paths
- **Jobs** - Verify jobs delegate to the correct services with correct arguments
- **Models** - Test validations, associations, and any model-level logic
- **Client libraries** - Test HTTP interactions, error handling, response parsing

#### Integration Tests (Middle Layer)
Integration tests verify that data flows correctly between services:
- Test that `PushEventHandler` correctly orchestrates `PushEventSaver` and `PushEventRelatedFetchesEnqueuer`
- Test that fetcher → saver → job enqueueing chains work end-to-end within a domain
- Verify database state after multi-service operations

#### End-to-End Test (Top Layer)
A single end-to-end test exercises the complete "happy path":
- Simulates receiving push events from GitHub
- Verifies events are saved to the database
- Confirms user and repository enrichment jobs complete
- Checks that all expected data is persisted correctly

This provides confidence that the entire system works together, not just individual pieces.

### External Service Boundaries

The system interacts with three external services, each with a specific testing strategy:

#### GitHub API (`Github::Client`)
**Strategy**: VCR cassettes

```ruby
# spec/lib/github/client_spec.rb
VCR.use_cassette("github/list_public_events") do
  events = client.list_public_events
  expect(events).to be_an(Array)
end
```

VCR records real HTTP responses and replays them in tests. This ensures we're testing against actual GitHub API behavior without hitting the API on every test run.

#### GitHub Avatars (`Github::AvatarsClient`)
**Strategy**: VCR cassettes

Same approach as the GitHub API client—VCR captures real avatar download responses for replay.

#### S3 Storage (`AvatarStorage::S3`)
**Strategy**: LocalStack integration

```ruby
# Tests run against LocalStack (local S3-compatible service)
# docker-compose includes localstack for test environment
storage = AvatarStorage::S3.new  # Configured to hit localhost:4566
storage.upload(key: "test/avatar.jpg", body: file, content_type: "image/jpeg")
expect(storage.exists?(key: "test/avatar.jpg")).to be true
```

LocalStack provides a real S3-compatible API locally, allowing us to test actual S3 operations without AWS credentials or costs.

### Mocking Strategy: Test at the Boundaries

Outside of boundary tests, we mock/stub external dependencies:

```ruby
# In service specs, stub the gateway (which wraps the client)
let(:gateway) { instance_double(GithubGateway) }
let(:service) { GithubUserFetcher.new(gateway: gateway) }

before do
  allow(gateway).to receive(:get_user).and_return(user_data)
end
```

**Why this approach**:
- `GithubGateway`, `Github::AvatarsClient`, and `AvatarStorage::S3` are the **boundaries** of our application
- These boundaries are tested once with real interactions (VCR/LocalStack)
- All other tests mock these boundaries, keeping tests fast and focused
- If a boundary test passes, we trust the real interaction works
- If a unit test passes with mocked boundaries, we trust the business logic works

This separation means:
- Boundary tests catch "did GitHub change their API?" issues
- Unit tests catch "did we break our logic?" issues
- Neither test suite is slowed down by the other's concerns

### What We Test

| Component | Test Type | External Dependencies |
|-----------|-----------|----------------------|
| `Github::Client` | VCR integration | Real GitHub API (recorded) |
| `Github::AvatarsClient` | VCR integration | Real avatar URLs (recorded) |
| `AvatarStorage::S3` | LocalStack integration | LocalStack S3 |
| `GithubGateway` | Unit (mocked client) | None |
| All services | Unit (mocked boundaries) | None |
| All jobs | Unit (mocked services) | None |
| Full pipeline | E2E (mocked HTTP) | None |

---

## Observability

### Logging Strategy

Logs are written to stdout/stderr for Docker compatibility:

| Log Level | Content |
|-----------|---------|
| INFO | Ingestion cycles, job starts/completions, records saved |
| WARN | Rate limit warnings, skipped actors, transient errors |
| ERROR | Permanent failures, unexpected exceptions |
| DEBUG | Rate limit state, fetch guard decisions |

### Key Log Messages

```
# Successful flow
INFO: Fetching public events from GitHub
INFO: Fetched 30 events, enqueueing jobs
INFO: Saved GitHub user: octocat (id: 583231)
INFO: Skipping fetch - data is fresh (last updated 2 minutes ago)

# Rate limiting
WARN: Rate limit low - 5 remaining of 60
INFO: Rate limit reached, sleeping for 3542 seconds

# Errors
ERROR: GitHub API error: 404 Not Found for user deleted_user
WARN: Unknown actor type, skipping user fetch: https://api.github.com/orgs/github
```

### Verification Checklist

To verify the system is working:

1. **Check logs**: `docker compose logs -f` should show ingestion cycles
2. **Check database**:
   ```sql
   SELECT COUNT(*) FROM github_push_events;  -- Should increase
   SELECT COUNT(*) FROM github_users;         -- Should have enriched users
   SELECT COUNT(*) FROM github_repositories;  -- Should have enriched repos
   ```
3. **Check jobs**: Sidekiq dashboard (if enabled) or job queue counts
4. **Timeline**: Events should appear within 60-90 seconds of running

---

## Summary

This system balances the competing constraints of data freshness, API budget, and operational simplicity. Key design choices:

1. **Fetch Guards** reduce API calls by 90%+ for repeat entities
2. **Idempotent savers** guarantee data correctness regardless of retries
3. **Background jobs** provide resilience and scalability
4. **Proactive rate limiting** prevents wasted requests
5. **Simple patterns** make the system easy to understand and debug

The architecture is intentionally conservative—prioritizing reliability and correctness over optimization. This foundation supports future enhancements (webhooks, more event types, advanced analytics) when requirements evolve.
