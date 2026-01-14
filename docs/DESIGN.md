# System Design Document

This document describes the architectural decisions and design patterns used in the StrongMind GitHub Ingestion system.

## Table of Contents

1. [Overview](#overview)
2. [Rate Limiting](#rate-limiting)
3. [Data Modeling](#data-modeling)
4. [Push Event Enrichment](#push-event-enrichment)
5. [Idempotency Guarantees](#idempotency-guarantees)

---

## Overview

This system ingests GitHub push events from the public events API and enriches them with detailed user and repository data. The architecture prioritizes:

- **Correctness over efficiency** - Data consistency is guaranteed even if some API calls are duplicated
- **Resilience** - Graceful handling of rate limits, transient failures, and malformed data
- **Observability** - Clear logging at each stage of processing

---

## Rate Limiting

### Architecture

The rate limiting system uses a two-layer architecture with pluggable storage backends:

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Github::Client │ ──▶ │ Github::RateLimiter │ ──▶ │ Storage Backend │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

**Components:**
- `Github::Client` - Makes HTTP requests and extracts rate limit headers from responses
- `Github::RateLimiter` - Manages rate limit state and enforces throttling
- Storage backends - Persist rate limit state (`Memory` for dev/test, `Redis` for production)

### Rate Limit Detection

The system intelligently distinguishes between rate limit errors and other 403 responses:

| Response | Condition | Error Type |
|----------|-----------|------------|
| 429 | Always | `RateLimitError` |
| 403 | `X-RateLimit-Remaining: 0` | `RateLimitError` |
| 403 | `retry-after` header present | `RateLimitError` (secondary limit) |
| 403 | Body contains "rate limit" | `RateLimitError` |
| 403 | Otherwise | `ClientError` (access denied) |
| 5xx | Server error | `ServerError` |
| 304 | Not modified | `NotModifiedError` |

This distinction is critical because:
- Rate limit 403s should trigger retry with backoff
- Access denied 403s should be discarded (no point retrying)

### Throttling Behavior

**Before each request:**
1. `RateLimiter#check_limit` reads stored rate limit state
2. If `remaining == 0` and reset time is in the future, calculate sleep duration
3. Sleep for `reset_time - now + 5 seconds` (buffer to avoid edge cases)
4. Minimum sleep is 1 second to prevent tight loops

**After each response:**
1. Extract `X-RateLimit-Remaining`, `X-RateLimit-Limit`, `X-RateLimit-Reset` headers
2. Store values with TTL of `reset_time - now + 10 seconds`

### Storage Backends

**Memory Backend** (`Github::Storage::Memory`):
- Thread-safe with `Monitor` synchronization
- Stores `{ value: json, expires_at: timestamp }`
- TTL-based expiration checked on read
- Suitable for single-process environments (development, testing)

**Redis Backend** (`Storage::Redis`):
- Supports both direct Redis clients and `ConnectionPool` objects
- Uses `SETEX` for atomic set-with-expiration
- Key format: `github:rate_limit:{resource}` (default resource: "core")
- TTL: `reset_time - now + 10 seconds`, minimum 60 seconds
- Required for multi-process production deployments

### Job Retry Strategy

Jobs use different retry strategies based on error type:

```ruby
# Transient errors - exponential backoff
retry_on Github::Client::ServerError,
  wait: :exponentially_longer,
  attempts: 5

# Rate limits - wait for reset window
retry_on Github::Client::RateLimitError,
  wait: 1.hour,
  attempts: 3

# Permanent errors - don't retry
discard_on Github::Client::ClientError
```

### Logging

The rate limiter provides visibility through logging:

| Log Level | Event |
|-----------|-------|
| DEBUG | Every rate limit check (remaining requests, reset time) |
| WARN | Remaining requests < 10% of limit |
| WARN | Sleeping due to exhausted limit |
| INFO | Rate limit reset, requests resuming |

---

## Data Modeling

### Design Principles

1. **GitHub IDs as Primary Keys** - All models use GitHub's native IDs as primary keys for idempotency
2. **Raw + Structured Storage** - Push events store both raw JSON and extracted fields
3. **Flattened Nested Objects** - Nested API objects (like `license`) are flattened with prefixes
4. **Timestamp Disambiguation** - GitHub's timestamps stored as `github_created_at`/`github_updated_at` to avoid conflict with Rails timestamps

### Schema Overview

#### GithubPushEvent

Stores push events with minimal processing and full raw data for audit:

| Column | Type | Description |
|--------|------|-------------|
| `id` | string (PK) | GitHub event ID (e.g., "12345678901") |
| `actor_id` | bigint | GitHub user ID of the actor |
| `repository_id` | bigint | GitHub repository ID |
| `push_id` | bigint | Unique push ID within the repository |
| `ref` | string | Git reference (e.g., "refs/heads/main") |
| `head` | string | Commit SHA after the push |
| `before` | string | Commit SHA before the push |
| `raw` | jsonb | Full unprocessed GitHub API response |
| `created_at` | datetime | Rails timestamp |
| `updated_at` | datetime | Rails timestamp |

**Why store raw data?**
- Audit trail for debugging and compliance
- Future-proofing: extract additional fields without re-fetching
- Enables replay if processing logic changes

#### GithubUser

Stores enriched user data from the GitHub Users API (~30 fields):

| Category | Fields |
|----------|--------|
| Identity | `id` (PK), `login`, `node_id`, `type`, `site_admin` |
| Profile | `name`, `email`, `bio`, `company`, `location`, `blog` |
| Social | `twitter_username`, `hireable` |
| Statistics | `public_repos`, `public_gists`, `followers`, `following` |
| URLs | `avatar_url`, `html_url`, `url`, and 9 resource URLs |
| Timestamps | `github_created_at`, `github_updated_at`, `created_at`, `updated_at` |

#### GithubRepository

Stores enriched repository data from the GitHub Repos API (~80 fields):

| Category | Fields |
|----------|--------|
| Identity | `id` (PK), `name`, `full_name`, `node_id` |
| Ownership | `owner_id` (extracted from nested `owner.id`) |
| Visibility | `private`, `visibility`, `archived`, `disabled` |
| Description | `description`, `homepage`, `language`, `topics` (jsonb) |
| Statistics | `stargazers_count`, `watchers_count`, `forks_count`, `open_issues_count`, `size` |
| Features | `has_issues`, `has_wiki`, `has_pages`, `has_discussions`, etc. |
| License | `license_key`, `license_name`, `license_spdx_id`, `license_url`, `license_node_id` |
| URLs | `html_url`, `git_url`, `ssh_url`, `clone_url`, and ~50 API URLs |
| Git | `default_branch`, `pushed_at` |
| Timestamps | `github_created_at`, `github_updated_at`, `created_at`, `updated_at` |

### Persistence Patterns

**Why `find_or_initialize_by` + `update!` instead of `upsert`?**

```ruby
# We use this pattern:
record = Model.find_or_initialize_by(id: github_id)
record.update!(attributes.except(:id))

# Instead of:
Model.upsert(attributes, unique_by: :id)  # Problematic with JSONB
```

PostgreSQL has issues comparing JSONB columns in upsert's conflict detection. The find-then-update pattern avoids this while maintaining idempotency.

**Attribute Mapping:**

Saver services handle the translation from GitHub API responses to database columns:
- Direct mappings: `data["login"]` → `login`
- Nested extractions: `data.dig("owner", "id")` → `owner_id`
- Flattened objects: `data.dig("license", "key")` → `license_key`
- Timestamp renames: `data["created_at"]` → `github_created_at`

---

## Push Event Enrichment

### Flow Overview

```
┌─────────────────────────────────────┐
│ FetchAndEnqueuePushEventsService    │
│ (Entry point - cron/manual)         │
└──────────────┬──────────────────────┘
               │ Fetches events from GitHub API
               │ Enqueues HandlePushEventJob for each
               ▼
┌─────────────────────────────────────┐
│ HandlePushEventJob                  │
│ → PushEventHandler                  │
└──────────────┬──────────────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
┌──────────────┐  ┌──────────────────────────┐
│PushEventSaver│  │PushEventRelatedFetches   │
│              │  │Enqueuer                  │
│Saves event   │  │                          │
│to database   │  │Enqueues enrichment jobs: │
│              │  │• FetchAndSaveGithubRepo  │
│              │  │• FetchAndSaveGithubUser  │
│              │  │  (if actor is :user)     │
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

### Actor Type Detection

The system determines actor type from the actor URL in the event payload:

| URL Pattern | Actor Type | User Job Enqueued? |
|-------------|------------|-------------------|
| `/users/octocat` | `:user` | Yes |
| `/users/github-actions[bot]` | `:bot` | No |
| `/orgs/github` | `:unknown` | No |
| (missing) | `nil` | No |

**Implementation** (`PushEventDataExtractor#actor`):
```ruby
# Match /users/{username} pattern
match = url.match(%r{^https?://[^/]+/users/([^/]+)$})
return :unknown unless match

username = match[1]
username.end_with?("[bot]") ? :bot : :user
```

**Why skip bots and orgs?**
- Bot accounts have limited profile data
- Organization URLs use `/orgs/` not `/users/` - different API endpoint
- Repository jobs are always enqueued regardless of actor type

### Service Separation: Fetcher vs Saver

Each enrichment flow is split into two services:

**Fetcher** - Handles API communication:
```ruby
class GithubUserFetcher
  def call(username:)
    user_data = gateway.get_user(username: username)
    GithubUserSaver.new.call(user_data: user_data)
  end
end
```

**Saver** - Handles persistence and mapping:
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
- Fetchers can be tested by stubbing the gateway
- Savers can be tested with raw data hashes (no API mocking)
- Savers are reusable from other sources (webhooks, imports, admin tools)
- Clear separation of concerns

---

## Idempotency Guarantees

### What IS Idempotent

**Database operations:**
- `PushEventSaver` uses `find_or_create_by!(id: event_id)`
- `GithubUserSaver` uses `find_or_initialize_by(id:) + update!`
- `GithubRepositorySaver` uses `find_or_initialize_by(id:) + update!`

All use GitHub IDs as primary keys - database constraints prevent duplicates.

**Multiple executions produce the same result:**
```ruby
# Safe to call multiple times
GithubUserSaver.new.call(user_data: data)  # Creates record
GithubUserSaver.new.call(user_data: data)  # Updates with same data
# Result: 1 record with correct data
```

### What ISN'T Idempotent (And Why That's OK)

**Job enqueueing is not idempotent:**
- `PushEventRelatedFetchesEnqueuer` enqueues jobs every time it's called
- If `HandlePushEventJob` retries, it re-enqueues fetch jobs
- No deduplication at the queue level

**Why this is acceptable:**
1. **Data correctness is guaranteed** - Saver services prevent duplicate records
2. **Final state is always correct** - Duplicate jobs update the same record safely
3. **Rare occurrence** - Retries happen infrequently
4. **Generous API limits** - GitHub allows 5,000 requests/hour for authenticated apps
5. **No user impact** - Duplicate work is invisible to users

**Example scenario:**
```
HandlePushEventJob retries due to database deadlock:
  → PushEventSaver: returns existing event (idempotent) ✓
  → Enqueuer: enqueues duplicate fetch jobs ✗
  → 2 FetchAndSaveGithubUserJobs execute
  → Both fetch from API (redundant)
  → Both call GithubUserSaver (idempotent)
  → Result: 1 user record, correct data, 1 wasted API call
```

**Trade-off:** The system prioritizes correctness over efficiency.

---

## Future Considerations

### Planned Enhancements

- **Conditional fetching** - Check data freshness before re-fetching to reduce API usage
- **Avatar storage** - Download and store user avatars in object storage
- **Secondary rate limit handling** - More sophisticated handling of GitHub's abuse detection

### Potential Improvements

- Webhook support instead of polling
- GraphQL API for more efficient data fetching
- ETag-based caching for conditional requests
- Data retention policies

---

*Last updated: January 2026*
