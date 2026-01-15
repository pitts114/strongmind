class FetchGuard
  def initialize(staleness_threshold_minutes: nil)
    @staleness_threshold_minutes = staleness_threshold_minutes
  end

  # Returns true if we should fetch, false otherwise.
  # Determines if a fetch is needed based on:
  # - Record existence (missing record = should fetch)
  # - Data staleness (old record = should fetch)
  #
  # Can be extended to check:
  # - In-flight tracking (another job is already fetching)
  # - Backoff/circuit breaker (recently failed)
  # - Permanent skip (known deleted/private resource)
  def should_fetch?(record:)
    # Always fetch if staleness checking is disabled
    return true if staleness_threshold_minutes.zero?

    # Fetch if record doesn't exist
    return true if record.nil?

    # Fetch if record is older than threshold
    threshold = staleness_threshold_minutes.minutes.ago
    record.updated_at < threshold
  end

  private

  attr_reader :staleness_threshold_minutes

  def staleness_threshold_minutes
    @staleness_threshold_minutes || ENV.fetch("STALENESS_THRESHOLD_MINUTES", "5").to_i
  end
end
