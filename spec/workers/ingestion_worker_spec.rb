require "rails_helper"

RSpec.describe IngestionWorker do
  let(:worker) { described_class.new(poll_interval: 1, sleep_unit: 0) }
  let(:service) { instance_double(FetchAndEnqueuePushEventsService) }

  before do
    allow(FetchAndEnqueuePushEventsService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(
      { events_fetched: 5, jobs_enqueued: 5 }
    )
  end

  describe "#initialize" do
    it "uses provided poll interval" do
      worker = described_class.new(poll_interval: 30, sleep_unit: 0)
      expect(worker.poll_interval).to eq(30)
    end

    it "uses ENV variable when no argument provided" do
      stub_const("ENV", ENV.to_hash.merge("INGESTION_POLL_INTERVAL" => "45"))
      worker = described_class.new(sleep_unit: 0)
      expect(worker.poll_interval).to eq(45)
    end

    it "uses default when no argument or ENV variable" do
      stub_const("ENV", ENV.to_hash.except("INGESTION_POLL_INTERVAL"))
      worker = described_class.new(sleep_unit: 0)
      expect(worker.poll_interval).to eq(60)
    end

    it "uses default when ENV variable is invalid" do
      stub_const("ENV", ENV.to_hash.merge("INGESTION_POLL_INTERVAL" => "invalid"))
      worker = described_class.new(sleep_unit: 0)
      expect(worker.poll_interval).to eq(60)
    end
  end

  describe "#start" do
    it "calls FetchAndEnqueuePushEventsService" do
      # Simulate worker running for one cycle then stopping
      allow(worker).to receive(:sleep_with_interruption_check) do
        worker.instance_variable_set(:@running, false)
      end

      worker.start

      expect(service).to have_received(:call).at_least(:once)
    end

    it "logs cycle completion" do
      allow(worker).to receive(:sleep_with_interruption_check) do
        worker.instance_variable_set(:@running, false)
      end

      # Allow other log messages
      allow(Rails.logger).to receive(:info)

      # Expect specific cycle completion message
      expect(Rails.logger).to receive(:info).with(
        "Fetch cycle completed: 5 events fetched, 5 jobs enqueued"
      )

      worker.start
    end

    context "when rate limit error occurs" do
      before do
        allow(service).to receive(:call).and_raise(
          Github::Client::RateLimitError.new("Rate limit", status_code: 403)
        )
        allow(worker).to receive(:sleep_with_interruption_check) do
          worker.instance_variable_set(:@running, false)
        end
      end

      it "logs warning and backs off" do
        expect(Rails.logger).to receive(:warn).with(/rate limit exceeded/i)
        expect(worker).to receive(:sleep_with_interruption_check).with(300)

        worker.start
      end
    end

    context "when server error occurs" do
      before do
        allow(service).to receive(:call).and_raise(
          Github::Client::ServerError.new("Server error", status_code: 500)
        )
        allow(worker).to receive(:sleep_with_interruption_check) do
          worker.instance_variable_set(:@running, false)
        end
      end

      it "logs error and retries with backoff" do
        expect(Rails.logger).to receive(:error).with(/server error/i)
        expect(worker).to receive(:sleep_with_interruption_check).with(30)

        worker.start
      end
    end

    context "when unexpected error occurs" do
      before do
        allow(service).to receive(:call).and_raise(StandardError.new("Boom!"))
        allow(worker).to receive(:sleep_with_interruption_check) do
          worker.instance_variable_set(:@running, false)
        end
      end

      it "logs error with backtrace and continues" do
        expect(Rails.logger).to receive(:error).with(/unexpected error/i)
        expect(worker).to receive(:sleep_with_interruption_check).with(30)

        worker.start
      end
    end
  end

  describe "signal handling" do
    before do
      # Stub logger to avoid "log writing failed" warnings from signal traps
      allow(Rails.logger).to receive(:info)
    end

    it "stops gracefully on SIGTERM" do
      allow(worker).to receive(:sleep_with_interruption_check) do
        # Simulate signal being sent during sleep
        Process.kill("TERM", Process.pid)
        worker.instance_variable_set(:@running, false)
      end

      expect { worker.start }.not_to raise_error
    end

    it "stops gracefully on SIGINT" do
      allow(worker).to receive(:sleep_with_interruption_check) do
        # Simulate Ctrl+C during sleep
        Process.kill("INT", Process.pid)
        worker.instance_variable_set(:@running, false)
      end

      expect { worker.start }.not_to raise_error
    end
  end
end
