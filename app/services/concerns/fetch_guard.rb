module FetchGuard
  extend ActiveSupport::Concern

  # Subclasses must implement:
  # - find_fresh_record(identifier:, threshold:) - query to find a fresh record
  #
  # Subclasses may override:
  # - staleness_threshold_minutes - defaults to STALENESS_THRESHOLD_MINUTES env var (5 min)

  # Returns the record if it exists and a fetch is not needed, nil otherwise.
  # A missing record means a fetch is needed.
  # Currently checks staleness, but can be extended to check:
  # - In-flight tracking (another job is already fetching)
  # - Backoff/circuit breaker (recently failed)
  # - Permanent skip (known deleted/private resource)
  def find_unless_fetch_needed(identifier:)
    return nil if staleness_threshold_minutes.zero?

    threshold = staleness_threshold_minutes.minutes.ago
    find_fresh_record(identifier: identifier, threshold: threshold)
  end

  private

  def staleness_threshold_minutes
    ENV.fetch("STALENESS_THRESHOLD_MINUTES", "5").to_i
  end

  def find_fresh_record(identifier:, threshold:)
    raise NotImplementedError, "Subclass must implement #find_fresh_record(identifier:, threshold:)"
  end
end
