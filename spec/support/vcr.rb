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

  # Filter sensitive data if needed in the future
  # config.filter_sensitive_data('<GITHUB_TOKEN>') { ENV['GITHUB_TOKEN'] }
end
