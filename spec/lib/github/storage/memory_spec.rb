require "spec_helper"
require_relative "../../../../lib/github/storage"
require_relative "../../../../lib/github/storage/memory"

RSpec.describe Github::Storage::Memory do
  subject(:storage) { described_class.new }

  describe "#get and #set" do
    it "stores and retrieves values" do
      storage.set("key1", "value1")
      expect(storage.get("key1")).to eq("value1")
    end

    it "returns nil for non-existent keys" do
      expect(storage.get("nonexistent")).to be_nil
    end

    it "overwrites existing values" do
      storage.set("key1", "value1")
      storage.set("key1", "value2")
      expect(storage.get("key1")).to eq("value2")
    end
  end

  describe "TTL support" do
    it "respects TTL and expires keys" do
      current_time = Time.now
      allow(Time).to receive(:now).and_return(current_time)

      storage.set("key1", "value1", ttl: 60)
      expect(storage.get("key1")).to eq("value1")

      # Simulate time passage beyond TTL
      allow(Time).to receive(:now).and_return(current_time + 61)
      expect(storage.get("key1")).to be_nil
    end

    it "allows keys without TTL to persist" do
      current_time = Time.now
      allow(Time).to receive(:now).and_return(current_time)

      storage.set("key1", "value1")
      expect(storage.get("key1")).to eq("value1")

      # Simulate time passage - key should still exist
      allow(Time).to receive(:now).and_return(current_time + 1000)
      expect(storage.get("key1")).to eq("value1")
    end
  end

  describe "#delete" do
    it "removes keys" do
      storage.set("key1", "value1")
      storage.delete("key1")
      expect(storage.get("key1")).to be_nil
    end

    it "is idempotent" do
      storage.delete("nonexistent")
      expect { storage.delete("nonexistent") }.not_to raise_error
    end
  end

  describe "#clear" do
    it "removes all keys" do
      storage.set("key1", "value1")
      storage.set("key2", "value2")
      storage.clear

      expect(storage.get("key1")).to be_nil
      expect(storage.get("key2")).to be_nil
    end
  end

  describe "#increment" do
    it "increments a counter from 0" do
      result = storage.increment("counter")
      expect(result).to eq(1)
      expect(storage.get("counter")).to eq("1")
    end

    it "increments an existing counter" do
      storage.set("counter", "5")
      result = storage.increment("counter")
      expect(result).to eq(6)
      expect(storage.get("counter")).to eq("6")
    end

    it "increments by custom amount" do
      storage.set("counter", "10")
      result = storage.increment("counter", amount: 5)
      expect(result).to eq(15)
      expect(storage.get("counter")).to eq("15")
    end

    it "is thread-safe" do
      threads = 10.times.map do
        Thread.new do
          100.times { storage.increment("counter") }
        end
      end

      threads.each(&:join)
      expect(storage.get("counter").to_i).to eq(1000)
    end
  end

  describe "#decrement" do
    it "decrements a counter from 0 (doesn't go negative)" do
      result = storage.decrement("counter")
      expect(result).to eq(0)
      expect(storage.get("counter")).to eq("0")
    end

    it "decrements an existing counter" do
      storage.set("counter", "10")
      result = storage.decrement("counter")
      expect(result).to eq(9)
      expect(storage.get("counter")).to eq("9")
    end

    it "decrements by custom amount" do
      storage.set("counter", "20")
      result = storage.decrement("counter", amount: 5)
      expect(result).to eq(15)
      expect(storage.get("counter")).to eq("15")
    end

    it "doesn't go below zero" do
      storage.set("counter", "3")
      result = storage.decrement("counter", amount: 10)
      expect(result).to eq(0)
      expect(storage.get("counter")).to eq("0")
    end

    it "is thread-safe" do
      storage.set("counter", "1000")

      threads = 10.times.map do
        Thread.new do
          100.times { storage.decrement("counter") }
        end
      end

      threads.each(&:join)
      expect(storage.get("counter").to_i).to eq(0)
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = 10.times.map do |i|
        Thread.new do
          100.times do |j|
            storage.set("key#{i}", "value#{j}")
            storage.get("key#{i}")
          end
        end
      end

      threads.each(&:join)
      expect(storage.get("key0")).to match(/value\d+/)
    end
  end
end
