# LocalStack S3 Setup

This directory contains initialization scripts for LocalStack, a local AWS cloud service emulator.

## Overview

LocalStack provides a local S3-compatible storage service for development and testing. This eliminates the need for real AWS credentials during development.

## Services Configured

- **S3**: Object storage service (port 4566)

## S3 Buckets

The following buckets are automatically created on startup:

- `user-avatars` - Storage for GitHub user avatar images

## Usage

### Starting LocalStack

```bash
docker-compose up localstack
```

LocalStack will automatically execute the initialization scripts in this directory when it's ready.

### Accessing LocalStack S3

**Endpoint**: `http://localhost:4566`

**AWS CLI (with awslocal)**:
```bash
# List buckets
awslocal s3 ls

# List objects in user-avatars bucket
awslocal s3 ls s3://user-avatars/

# Upload a file
awslocal s3 cp myfile.jpg s3://user-avatars/

# Download a file
awslocal s3 cp s3://user-avatars/myfile.jpg ./downloaded.jpg
```

**Ruby/Rails (via ActiveStorage)**:
```ruby
# Configuration is in config/storage.yml under "localstack"
# To use LocalStack storage:
# 1. Set RAILS_ENV=development (or configure your environment)
# 2. Configure ActiveStorage to use :localstack service
# 3. Upload files using ActiveStorage as normal

# Example:
user = GithubUser.first
user.avatar.attach(io: File.open('avatar.jpg'), filename: 'avatar.jpg')
user.avatar.url # Returns LocalStack S3 URL
```

## Configuration Files

### docker-compose.yml

```yaml
localstack:
  image: localstack/localstack:latest
  ports:
    - '4566:4566'
  environment:
    - SERVICES=s3
    - DEBUG=1
    - DATA_DIR=/tmp/localstack/data
  volumes:
    - './docker/localstack:/etc/localstack/init/ready.d'
    - 'localstack_data:/tmp/localstack'
```

### config/storage.yml

```yaml
localstack:
  service: S3
  access_key_id: test
  secret_access_key: test
  region: us-east-1
  bucket: user-avatars
  endpoint: http://localhost:4566
  force_path_style: true
```

## Credentials

LocalStack uses dummy credentials for development:

- **Access Key ID**: `test`
- **Secret Access Key**: `test`
- **Region**: `us-east-1`

These are not real AWS credentials and only work with LocalStack.

## Data Persistence

LocalStack data is persisted in a Docker volume named `localstack_data`. This means:

- Buckets and objects survive container restarts
- To reset all data: `docker-compose down -v` (removes volumes)
- To keep data between sessions: just use `docker-compose down`

## Initialization Scripts

Scripts in this directory (with `.sh` extension) are automatically executed when LocalStack is ready. Current scripts:

- `init-s3.sh` - Creates S3 buckets and sets permissions

## Troubleshooting

### LocalStack not starting

```bash
# Check LocalStack logs
docker-compose logs localstack

# Verify port 4566 is not in use
lsof -i :4566
```

### Buckets not created

```bash
# Check if initialization script ran
docker-compose logs localstack | grep "initialization"

# Manually run initialization
docker-compose exec localstack /etc/localstack/init/ready.d/init-s3.sh
```

### Cannot connect from Rails

Ensure:
1. LocalStack is running: `docker-compose ps`
2. Port 4566 is accessible: `curl http://localhost:4566/health`
3. Storage configuration is correct in `config/storage.yml`
4. `aws-sdk-s3` gem is installed: `bundle install`

## References

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [AWS SDK for Ruby](https://docs.aws.amazon.com/sdk-for-ruby/)
- [Rails ActiveStorage Guide](https://guides.rubyonrails.org/active_storage_overview.html)
