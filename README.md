# GitHub Event Ingestion System

A service that ingests GitHub push events, enriches them with user and repository data, and stores everything durably in PostgreSQL.

**[Design Brief](DESIGN_BRIEF.md)** - Architecture decisions, data modeling, rate limiting strategy, and testing approach.

---

# Production Deployment with Docker Compose

## Prerequisites

- Docker Desktop 4.0+ for macOS

## Quick Start

### Start the System

```bash
# Create environment file (uses working defaults)
cp .env.production.example .env.production

# Build and start all services
docker compose -f docker-compose.prod.yml --env-file .env.production up --build
```

This starts:
- **PostgreSQL** - Database for storing events and enriched data
- **Redis** - Rate limiting and caching
- **LocalStack** - S3-compatible object storage for avatars
- **Web** - Rails web server (serves Sidekiq dashboard)
- **Jobs** - Sidekiq background job processor
- **Ingestion** - Continuous GitHub event ingestion worker

### Run Ingestion (Manual One-Off)

The ingestion worker runs continuously when you start the system. To run a single ingestion cycle manually:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production run --rm --build ingest
```

### Run Tests

```bash
docker compose -f docker-compose.prod.yml --env-file .env.test.docker run --rm --build test
```

### View Logs

```bash
# All services
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f

# Specific service
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f ingestion
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f jobs
```

## How to Verify the System is Working

### Expected Logs

After starting the system, you should see logs indicating successful operation:

**Ingestion Worker Logs:**
```
ingestion  | Starting ingestion worker with poll interval: 60 seconds
ingestion  | Fetching public events from GitHub API...
ingestion  | Fetched 30 events, filtering for PushEvents...
ingestion  | Found 15 PushEvents, enqueueing for processing...
ingestion  | Successfully enqueued 15 push events for processing
ingestion  | Sleeping for 60 seconds before next fetch...
```

**Job Worker Logs:**
```
jobs  | Performing HandlePushEventJob...
jobs  | Saved push event: 12345678901
jobs  | Enqueuing FetchAndSaveGithubUserJob for user: octocat
jobs  | Enqueuing FetchAndSaveGithubRepositoryJob for repo: octocat/Hello-World
jobs  | Performed HandlePushEventJob in 0.5s
```

**Rate Limit Handling:**
When rate limits are reached, you'll see:
```
ingestion  | Rate limit reached. Backing off for 300 seconds...
```

### Database Tables to Check

Connect to the database:
```bash
docker compose -f docker-compose.prod.yml --env-file .env.production exec db psql -U postgres strongmind_server_production
```

Check ingested data:
```sql
-- Count push events
SELECT COUNT(*) FROM github_push_events;

-- View recent push events
SELECT id, actor_id, repository_id, ref, created_at
FROM github_push_events
ORDER BY created_at DESC
LIMIT 10;

-- Count enriched users
SELECT COUNT(*) FROM github_users;

-- View recent users
SELECT id, login, name, public_repos, followers
FROM github_users
ORDER BY updated_at DESC
LIMIT 10;

-- Count enriched repositories
SELECT COUNT(*) FROM github_repositories;

-- View recent repositories
SELECT id, full_name, stargazers_count, language
FROM github_repositories
ORDER BY updated_at DESC
LIMIT 10;
```

## Stop the System

```bash
# Stop services (preserves data)
docker compose -f docker-compose.prod.yml --env-file .env.production stop

# Stop and remove containers (preserves data volumes)
docker compose -f docker-compose.prod.yml --env-file .env.production down

# Stop and remove everything including data (DESTROYS DATA)
docker compose -f docker-compose.prod.yml --env-file .env.production down -v
```

## Common Operations

### Access Rails Console

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production exec jobs rails console
```

### Run Database Migrations

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production exec jobs rails db:migrate
```

### Check Service Status

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production ps
```

### Rebuild After Code Changes

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production up --build -d
```

## Environment Variables

See `.env.production.example` for all options. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY_BASE` | (required) | Rails session encryption key |
| `DATABASE_PASSWORD` | postgres | PostgreSQL password |
| `INGESTION_POLL_INTERVAL` | 60 | Seconds between GitHub API polls |
| `RAILS_LOG_LEVEL` | info | Log verbosity (debug/info/warn/error) |
| `AWS_ACCESS_KEY_ID` | test | S3 access key (use `test` for LocalStack) |
| `AWS_SECRET_ACCESS_KEY` | test | S3 secret key (use `test` for LocalStack) |
| `AWS_ENDPOINT_URL` | http://localstack:4566 | S3 endpoint URL |
| `AVATAR_S3_BUCKET` | user-avatars | S3 bucket for user avatars |

## Troubleshooting

### Services won't start

```bash
# Check logs for errors
docker compose -f docker-compose.prod.yml --env-file .env.production logs

# Verify all containers are running
docker compose -f docker-compose.prod.yml --env-file .env.production ps
```

### No events being ingested

1. Check ingestion worker logs for rate limit messages
2. Verify network connectivity to api.github.com
3. Check that the database is healthy

### Tests failing

```bash
# Run tests with verbose output
docker compose -f docker-compose.prod.yml --env-file .env.test.docker run --rm --build test bundle exec rspec --format documentation
```

# Local Development

For local development without Docker (requires local PostgreSQL, Redis, and LocalStack).

## Setup
1. **Create Environment File**
   ```bash
   # Copy the template (already has working defaults)
   cp .env.example .env
   ```

2. **Install Dependencies**
   ```bash
   bundle install
   ```

3. **Setup Database**
   ```bash
   rails db:prepare
   ```

## Sidekiq (Background Jobs)
```bash
bundle exec sidekiq
```

## Ingestion Worker
```bash
# Continuous polling (default)
bin/ingestion_worker

# Single fetch cycle (one-time)
bin/ingestion_worker --once
```
