# GitHub Event Ingestion System

A service that ingests GitHub push events, enriches them with user and repository data, and stores everything durably in PostgreSQL.

**[Design Brief](DESIGN_BRIEF.md)** - Architecture decisions, data modeling, rate limiting strategy, and testing approach.

---

# Development

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

## Server
`bundle exec rails server`

## Sidekiq
`bundle exec sidekiq`

# Production Deployment with Docker Compose

## Prerequisites
- Docker 20.10+ with Compose V2

## Quick Start

1. **Create Environment File**
   ```bash
   # Copy the template (already has working defaults)
   cp .env.production.example .env.production
   ```

2. **Build and Start Services**
   ```bash
   # Build images
   docker compose -f docker-compose.prod.yml --env-file .env.production --env-file .env.production build

   # Start all services
   docker compose -f docker-compose.prod.yml --env-file .env.production --env-file .env.production up -d
   ```

3. **Verify Everything Started**
   ```bash
   # Check service status
   docker compose -f docker-compose.prod.yml --env-file .env.production --env-file .env.production ps

   # Check logs
   docker compose -f docker-compose.prod.yml --env-file .env.production --env-file .env.production logs -f
   ```

   The web app will be available at http://localhost:3000

## Common Operations

### View Logs
```bash
# All services
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f

# Specific service
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f web
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f ingestion
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f jobs
```

### Restart Services
```bash
# Restart all services
docker compose -f docker-compose.prod.yml --env-file .env.production restart

# Restart specific service
docker compose -f docker-compose.prod.yml --env-file .env.production restart web
```

### Stop Services
```bash
# Stop all services (preserves data)
docker compose -f docker-compose.prod.yml --env-file .env.production stop

# Stop and remove containers (preserves data)
docker compose -f docker-compose.prod.yml --env-file .env.production down

# Stop and remove containers + volumes (DESTROYS DATA)
docker compose -f docker-compose.prod.yml --env-file .env.production down -v
```

### Access Rails Console
```bash
docker compose -f docker-compose.prod.yml --env-file .env.production exec web rails console
```

### Run Database Migrations Manually
```bash
docker compose -f docker-compose.prod.yml --env-file .env.production exec web rails db:migrate
```

### Rebuild After Code Changes
```bash
# Build new images
docker compose -f docker-compose.prod.yml --env-file .env.production build

# Restart services with new images
docker compose -f docker-compose.prod.yml --env-file .env.production up -d
```

## Monitoring

### Service Health
```bash
# Check container status
docker compose -f docker-compose.prod.yml --env-file .env.production ps

# Check resource usage
docker compose -f docker-compose.prod.yml --env-file .env.production stats
```

### Database Access
```bash
# Connect to PostgreSQL
docker compose -f docker-compose.prod.yml --env-file .env.production exec db psql -U postgres strongmind_server_production
```

### Redis CLI
```bash
# Connect to Redis
docker compose -f docker-compose.prod.yml --env-file .env.production exec redis redis-cli
```

## Environment Variables

See `.env.production.example` for complete list. The example file has working defaults for all required variables.

**Key Variables:**
- `SECRET_KEY_BASE` - Rails sessions/cookies key (128 hex chars)
- `DATABASE_PASSWORD` - Database password (default: postgres)
- `INGESTION_POLL_INTERVAL` - GitHub polling interval in seconds (default: 60)
- `RAILS_LOG_LEVEL` - Logging verbosity: debug, info, warn, error, fatal (default: info)
- `RAILS_MAX_THREADS` - Thread pool size for web/job workers

## Troubleshooting

### Services won't start
```bash
# Check logs for errors
docker compose -f docker-compose.prod.yml --env-file .env.production logs
```

### Database connection errors
```bash
# Ensure database is healthy
docker compose -f docker-compose.prod.yml --env-file .env.production ps db

# Check database logs
docker compose -f docker-compose.prod.yml --env-file .env.production logs db
```

### Ingestion worker not fetching
```bash
# Check ingestion worker logs
docker compose -f docker-compose.prod.yml --env-file .env.production logs ingestion
```
