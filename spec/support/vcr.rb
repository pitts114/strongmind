require "vcr"

VCR.configure do |config|
  # Store cassettes in spec/fixtures/vcr_cassettes
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"

  # Use webmock to intercept HTTP requests
  config.hook_into :webmock

  # Match requests on method and URI by default
  # Individual test files can override match_requests_on for specific needs
  config.default_cassette_options = {
    match_requests_on: [ :method, :uri ],
    record: :once
  }

  # Allow connections to localhost (for any local development servers)
  config.ignore_localhost = true

  # Allow real connections to LocalStack S3 (works in both local dev and Docker)
  # Local dev uses localhost:4566, Docker uses localstack:4566
  config.ignore_request do |request|
    uri = URI(request.uri)
    localstack_hosts = %w[localhost localstack]
    localstack_hosts.include?(uri.host) && uri.port == 4566
  end

  # Filter sensitive data if needed in the future
  # config.filter_sensitive_data('<GITHUB_TOKEN>') { ENV['GITHUB_TOKEN'] }
end
