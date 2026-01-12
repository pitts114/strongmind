class IngestionWorker
  # Default configuration
  DEFAULT_POLL_INTERVAL = 60  # seconds
  RATE_LIMIT_BACKOFF = 300    # 5 minutes
  ERROR_BACKOFF = 30          # 30 seconds

  attr_reader :poll_interval

  def initialize(poll_interval: nil, sleep_unit: 1)
    @poll_interval = parse_poll_interval(poll_interval)
    @sleep_unit = sleep_unit
    @running = false
  end

  def start
    setup_signal_handlers
    @running = true

    Rails.logger.info("IngestionWorker starting (poll interval: #{poll_interval}s)")

    while @running
      run_fetch_cycle
      sleep_with_interruption_check(poll_interval) if @running
    end

    Rails.logger.info("IngestionWorker stopped gracefully")
  end

  private

  def setup_signal_handlers
    # Graceful shutdown on SIGTERM (Docker, Kubernetes)
    # Note: Can't log from trap context, so just set flag
    Signal.trap("TERM") do
      @running = false
    end

    # Graceful shutdown on SIGINT (Ctrl+C)
    Signal.trap("INT") do
      @running = false
    end

    # Optional: SIGQUIT for debugging
    Signal.trap("QUIT") do
      @running = false
    end
  end

  def run_fetch_cycle
    result = FetchAndEnqueuePushEventsService.new.call

    Rails.logger.info(
      "Fetch cycle completed: #{result[:events_fetched]} events fetched, " \
      "#{result[:jobs_enqueued]} jobs enqueued"
    )
  rescue Github::Client::RateLimitError => e
    Rails.logger.warn(
      "GitHub rate limit exceeded (#{e.status_code}). " \
      "Sleeping for #{RATE_LIMIT_BACKOFF}s before retry."
    )
    sleep_with_interruption_check(RATE_LIMIT_BACKOFF)
  rescue Github::Client::ServerError => e
    Rails.logger.error(
      "GitHub server error (#{e.status_code}): #{e.message}. " \
      "Retrying in #{ERROR_BACKOFF}s."
    )
    sleep_with_interruption_check(ERROR_BACKOFF)
  rescue StandardError => e
    Rails.logger.error(
      "Unexpected error in fetch cycle: #{e.class} - #{e.message}\n" \
      "#{e.backtrace.first(5).join("\n")}"
    )
    sleep_with_interruption_check(ERROR_BACKOFF)
  end

  # Sleep in small increments to allow quick shutdown on signal
  def sleep_with_interruption_check(duration)
    end_time = Time.now + duration

    while @running && Time.now < end_time
      sleep(@sleep_unit)
    end
  end

  def parse_poll_interval(interval)
    if interval
      Integer(interval)
    elsif ENV["INGESTION_POLL_INTERVAL"]
      Integer(ENV["INGESTION_POLL_INTERVAL"])
    else
      DEFAULT_POLL_INTERVAL
    end
  rescue ArgumentError
    Rails.logger.warn(
      "Invalid poll interval (#{interval || ENV['INGESTION_POLL_INTERVAL']}), " \
      "using default: #{DEFAULT_POLL_INTERVAL}s"
    )
    DEFAULT_POLL_INTERVAL
  end
end
