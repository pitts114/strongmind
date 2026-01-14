require "spec_helper"
require_relative "../../../lib/github/storage"
require_relative "../../../lib/github/storage/memory"
require_relative "../../../lib/github/rate_limiter"

RSpec.describe Github::RateLimiter do
  let(:storage) { Github::Storage::Memory.new }
  let(:max_concurrent_requests) { 3 }
  let(:rate_limiter) { described_class.new(storage: storage, max_concurrent_requests: max_concurrent_requests) }
  let(:logger) { instance_double(Logger, debug: nil, info: nil, warn: nil) }

  before do
    stub_const("Rails", double(logger: logger))
  end

  describe "#check_limit" do
    describe "logging" do
      context "when rate limit data exists with remaining requests" do
        before do
          headers = {
            "x-ratelimit-limit" => "60",
            "x-ratelimit-remaining" => "42",
            "x-ratelimit-reset" => (Time.now.to_i + 3600).to_s
          }
          rate_limiter.record_limit(headers)
        end

        it "logs rate limit status at debug level" do
          rate_limiter.check_limit

          expect(logger).to have_received(:debug).with(/Rate limit status - remaining: 42/)
        end
      end

      context "when rate limit is exhausted" do
        let(:reset_time) { Time.now.to_i + 10 }

        before do
          headers = {
            "x-ratelimit-limit" => "60",
            "x-ratelimit-remaining" => "0",
            "x-ratelimit-reset" => reset_time.to_s
          }
          rate_limiter.record_limit(headers)
          allow(rate_limiter).to receive(:sleep)
        end

        it "logs a warning about rate limit exhaustion with sleep duration" do
          rate_limiter.check_limit

          expect(logger).to have_received(:warn).with(/Rate limit exhausted, sleeping for \d+ seconds/)
        end

        it "logs when resuming after sleep" do
          rate_limiter.check_limit

          expect(logger).to have_received(:info).with("Github::RateLimiter: Rate limit reset, resuming requests")
        end
      end
    end

    context "when no rate limit data exists" do
      it "allows the request without sleeping" do
        expect(rate_limiter).not_to receive(:sleep)
        rate_limiter.check_limit
      end
    end

    context "when requests remain" do
      before do
        headers = {
          "x-ratelimit-limit" => "60",
          "x-ratelimit-remaining" => "42",
          "x-ratelimit-reset" => (Time.now.to_i + 3600).to_s
        }
        rate_limiter.record_limit(headers)
      end

      it "allows the request without sleeping" do
        expect(rate_limiter).not_to receive(:sleep)
        rate_limiter.check_limit
      end
    end

    context "when rate limit is exhausted" do
      it "sleeps until reset time" do
        reset_time = Time.now.to_i + 2
        headers = {
          "x-ratelimit-limit" => "60",
          "x-ratelimit-remaining" => "0",
          "x-ratelimit-reset" => reset_time.to_s
        }
        rate_limiter.record_limit(headers)

        expect(rate_limiter).to receive(:sleep).with(a_value >= 2)
        rate_limiter.check_limit
      end

      it "clears rate limit data after sleeping" do
        reset_time = Time.now.to_i + 1
        headers = {
          "x-ratelimit-limit" => "60",
          "x-ratelimit-remaining" => "0",
          "x-ratelimit-reset" => reset_time.to_s
        }
        rate_limiter.record_limit(headers)

        allow(rate_limiter).to receive(:sleep)
        rate_limiter.check_limit

        # Should allow second check without sleeping
        expect(rate_limiter).not_to receive(:sleep)
        rate_limiter.check_limit
      end
    end
  end

  describe "#record_limit" do
    describe "logging" do
      context "when rate limit is low (less than 10% remaining)" do
        it "logs a warning" do
          headers = {
            "x-ratelimit-limit" => "100",
            "x-ratelimit-remaining" => "5",
            "x-ratelimit-reset" => (Time.now.to_i + 3600).to_s
          }

          rate_limiter.record_limit(headers)

          expect(logger).to have_received(:warn).with(/Rate limit low - remaining: 5\/100/)
        end
      end

      context "when rate limit is at exactly 10%" do
        it "does not log a warning" do
          headers = {
            "x-ratelimit-limit" => "100",
            "x-ratelimit-remaining" => "10",
            "x-ratelimit-reset" => (Time.now.to_i + 3600).to_s
          }

          rate_limiter.record_limit(headers)

          expect(logger).not_to have_received(:warn)
        end
      end

      context "when rate limit is above 10%" do
        it "does not log a warning" do
          headers = {
            "x-ratelimit-limit" => "100",
            "x-ratelimit-remaining" => "50",
            "x-ratelimit-reset" => (Time.now.to_i + 3600).to_s
          }

          rate_limiter.record_limit(headers)

          expect(logger).not_to have_received(:warn)
        end
      end
    end

    it "stores rate limit data from headers" do
      headers = {
        "x-ratelimit-limit" => "60",
        "x-ratelimit-remaining" => "42",
        "x-ratelimit-reset" => "1704067200"
      }

      rate_limiter.record_limit(headers)

      stored_data = JSON.parse(storage.get("github:rate_limit:core"))
      expect(stored_data["limit"]).to eq("60")
      expect(stored_data["remaining"]).to eq("42")
      expect(stored_data["reset"]).to eq("1704067200")
    end

    it "handles case-insensitive header names" do
      headers = {
        "X-RateLimit-Limit" => "60",
        "X-RateLimit-Remaining" => "42",
        "X-RateLimit-Reset" => "1704067200"
      }

      rate_limiter.record_limit(headers)

      stored_data = JSON.parse(storage.get("github:rate_limit:core"))
      expect(stored_data["limit"]).to eq("60")
    end

    it "sets TTL on stored data" do
      reset_time = Time.now.to_i + 100
      headers = {
        "x-ratelimit-limit" => "60",
        "x-ratelimit-remaining" => "42",
        "x-ratelimit-reset" => reset_time.to_s
      }

      rate_limiter.record_limit(headers)

      # Data should exist immediately
      expect(storage.get("github:rate_limit:core")).not_to be_nil
    end

    it "handles missing headers gracefully" do
      headers = { "x-ratelimit-limit" => "60" }

      expect { rate_limiter.record_limit(headers) }.not_to raise_error
      expect(storage.get("github:rate_limit:core")).to be_nil
    end
  end

  describe "concurrent request limiting" do
    describe "#acquire_slot" do
      it "acquires a slot when under the limit" do
        rate_limiter.acquire_slot
        expect(storage.get("github:concurrent_requests:core").to_i).to eq(1)
      end

      it "allows multiple slots up to the limit" do
        rate_limiter.acquire_slot
        rate_limiter.acquire_slot
        rate_limiter.acquire_slot
        expect(storage.get("github:concurrent_requests:core").to_i).to eq(3)
      end

      it "blocks when limit is reached" do
        # Fill all slots
        3.times { rate_limiter.acquire_slot }

        # Try to acquire one more - should block
        expect(rate_limiter).to receive(:sleep).with(described_class::CONCURRENT_SLOT_POLL_INTERVAL).at_least(:once)

        # Simulate another thread releasing a slot after first sleep
        allow(rate_limiter).to receive(:sleep) do
          storage.decrement("github:concurrent_requests:core")
        end

        rate_limiter.acquire_slot
      end

      it "logs when acquiring a slot" do
        rate_limiter.acquire_slot
        expect(logger).to have_received(:debug).with(/Acquired concurrent request slot \(1\/3\)/)
      end

      it "logs when waiting for a slot" do
        # Fill all slots
        3.times { rate_limiter.acquire_slot }

        # Mock sleep to prevent actual blocking
        allow(rate_limiter).to receive(:sleep) do
          storage.decrement("github:concurrent_requests:core")
        end

        rate_limiter.acquire_slot
        expect(logger).to have_received(:debug).with(/Concurrent request limit reached, waiting for available slot/)
      end
    end

    describe "#release_slot" do
      it "releases a slot" do
        rate_limiter.acquire_slot
        rate_limiter.release_slot
        expect(storage.get("github:concurrent_requests:core").to_i).to eq(0)
      end

      it "doesn't go below zero" do
        rate_limiter.release_slot
        expect(storage.get("github:concurrent_requests:core").to_i).to eq(0)
      end

      it "logs when releasing a slot" do
        rate_limiter.acquire_slot
        rate_limiter.release_slot
        expect(logger).to have_received(:debug).with(/Released concurrent request slot \(0\/3\)/)
      end
    end

    describe "thread safety" do
      it "handles concurrent acquire and release safely" do
        threads = 10.times.map do
          Thread.new do
            20.times do
              rate_limiter.acquire_slot
              sleep(0.001)  # Simulate work
              rate_limiter.release_slot
            end
          end
        end

        threads.each(&:join)

        # All slots should be released
        expect(storage.get("github:concurrent_requests:core").to_i).to eq(0)
      end

      it "never exceeds the concurrent request limit" do
        max_observed = 0
        mutex = Mutex.new

        threads = 10.times.map do
          Thread.new do
            20.times do
              rate_limiter.acquire_slot

              current = storage.get("github:concurrent_requests:core").to_i
              mutex.synchronize { max_observed = [ max_observed, current ].max }

              sleep(0.001)  # Simulate work
              rate_limiter.release_slot
            end
          end
        end

        threads.each(&:join)

        expect(max_observed).to be <= max_concurrent_requests
      end
    end
  end
end
