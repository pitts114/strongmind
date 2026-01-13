require "rails_helper"

RSpec.describe Storage::Redis do
  let(:redis) { ::Redis.new }
  subject(:storage) { described_class.new(redis: redis) }

  before do
    # Clear Redis before each test
    redis.flushdb
  end

  after do
    redis.close
  end

  describe "#get and #set" do
    it "stores and retrieves values" do
      storage.set("test:key1", "value1")
      expect(storage.get("test:key1")).to eq("value1")
    end

    it "returns nil for non-existent keys" do
      expect(storage.get("test:nonexistent")).to be_nil
    end

    it "overwrites existing values" do
      storage.set("test:key1", "value1")
      storage.set("test:key1", "value2")
      expect(storage.get("test:key1")).to eq("value2")
    end
  end

  describe "TTL support" do
    it "sets TTL when specified" do
      storage.set("test:key1", "value1", ttl: 60)

      # Verify key exists
      expect(storage.get("test:key1")).to eq("value1")

      # Verify TTL is set (should be between 1 and 60 seconds)
      ttl = redis.ttl("test:key1")
      expect(ttl).to be_between(1, 60)
    end

    it "does not set TTL when not specified" do
      storage.set("test:key1", "value1")

      # Verify key exists
      expect(storage.get("test:key1")).to eq("value1")

      # Verify no expiration set (-1 means key persists forever)
      expect(redis.ttl("test:key1")).to eq(-1)
    end
  end

  describe "#delete" do
    it "removes keys" do
      storage.set("test:key1", "value1")
      storage.delete("test:key1")
      expect(storage.get("test:key1")).to be_nil
    end

    it "is idempotent" do
      storage.delete("test:nonexistent")
      expect { storage.delete("test:nonexistent") }.not_to raise_error
    end
  end
end
