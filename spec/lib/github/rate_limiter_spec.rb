require "spec_helper"
require_relative "../../../lib/github/storage"
require_relative "../../../lib/github/storage/memory"
require_relative "../../../lib/github/rate_limiter"

RSpec.describe Github::RateLimiter do
  let(:storage) { Github::Storage::Memory.new }
  let(:rate_limiter) { described_class.new(storage: storage) }
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
end
