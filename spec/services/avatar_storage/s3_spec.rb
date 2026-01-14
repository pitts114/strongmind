# frozen_string_literal: true

require "rails_helper"

RSpec.describe AvatarStorage::S3 do
  let(:storage) { described_class.new }

  # Fixed test keys for easy cleanup
  let(:test_keys) do
    [
      "test-avatars/basic.txt",
      "test-avatars/with-content-type.png",
      "test-avatars/binary.bin",
      "test-avatars/from-io.txt",
      "test-avatars/exists-check.txt",
      "test-avatars/to-delete.txt"
    ]
  end

  after do
    test_keys.each { |key| storage.delete(key: key) }
  end

  describe "#upload" do
    it "uploads a file successfully" do
      result = storage.upload(key: "test-avatars/basic.txt", body: "test content")

      expect(result).to be true
    end

    it "uploads a file with content type" do
      result = storage.upload(key: "test-avatars/with-content-type.png", body: "fake image data", content_type: "image/png")

      expect(result).to be true
    end

    it "uploads binary data" do
      binary_data = "\x00\x01\x02\x03\x04\x05"

      result = storage.upload(key: "test-avatars/binary.bin", body: binary_data)

      expect(result).to be true
    end

    it "uploads from an IO object" do
      io = StringIO.new("content from io")

      result = storage.upload(key: "test-avatars/from-io.txt", body: io)

      expect(result).to be true
    end
  end

  describe "#exists?" do
    context "when the file exists" do
      it "returns true" do
        storage.upload(key: "test-avatars/exists-check.txt", body: "test content")

        expect(storage.exists?(key: "test-avatars/exists-check.txt")).to be true
      end
    end

    context "when the file does not exist" do
      it "returns false" do
        expect(storage.exists?(key: "test-avatars/non-existent.txt")).to be false
      end
    end
  end

  describe "#delete" do
    context "when the file exists" do
      it "deletes the file and returns true" do
        storage.upload(key: "test-avatars/to-delete.txt", body: "test content")

        result = storage.delete(key: "test-avatars/to-delete.txt")

        expect(result).to be true
        expect(storage.exists?(key: "test-avatars/to-delete.txt")).to be false
      end
    end

    context "when the file does not exist" do
      it "returns false" do
        result = storage.delete(key: "test-avatars/non-existent.txt")

        expect(result).to be false
      end
    end
  end

  describe "initialization" do
    it "uses bucket from ENV" do
      expect(storage.send(:bucket)).to eq(ENV.fetch("AVATAR_S3_BUCKET", "user-avatars"))
    end

    it "can override bucket via parameter" do
      custom_storage = described_class.new(bucket: "custom-bucket")

      expect(custom_storage.send(:bucket)).to eq("custom-bucket")
    end
  end
end
