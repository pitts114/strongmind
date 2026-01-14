# frozen_string_literal: true

require "rails_helper"

RSpec.describe AvatarDownloadAndUploadService do
  let(:storage) { instance_double(AvatarStorage::S3) }
  let(:client) { instance_double(Github::AvatarsClient) }
  let(:key_deriver) { instance_double(AvatarKeyDeriver) }
  let(:service) { described_class.new(storage: storage, client: client, key_deriver: key_deriver) }

  let(:avatar_url) { "https://avatars.githubusercontent.com/u/178611968?v=4" }
  let(:expected_key) { "avatars/178611968" }
  let(:image_data) { "\x89PNG\r\n\x1a\n" }
  let(:content_type) { "image/png" }

  describe "#call" do
    before do
      allow(key_deriver).to receive(:call).with(url: avatar_url).and_return(expected_key)
    end

    context "when avatar already exists in storage" do
      before do
        allow(storage).to receive(:exists?).with(key: expected_key).and_return(true)
      end

      it "skips upload and returns skipped result" do
        result = service.call(avatar_url: avatar_url)

        expect(result).to eq({ key: expected_key, uploaded: false, skipped: true })
      end

      it "does not call client.download" do
        allow(client).to receive(:download)

        service.call(avatar_url: avatar_url)

        expect(client).not_to have_received(:download)
      end

      it "does not call storage.upload" do
        allow(storage).to receive(:upload)

        service.call(avatar_url: avatar_url)

        expect(storage).not_to have_received(:upload)
      end
    end

    context "when avatar does not exist in storage" do
      let(:temp_file) { Tempfile.new(["test", ".tmp"], binmode: true) }

      before do
        temp_file.write(image_data)
        temp_file.rewind

        allow(storage).to receive(:exists?).with(key: expected_key).and_return(false)
        allow(storage).to receive(:upload).and_return(true)
        allow(client).to receive(:download)
          .with(url: avatar_url)
          .and_return({ temp_file: temp_file, content_type: content_type })
      end

      after do
        temp_file.close unless temp_file.closed?
        temp_file.unlink if temp_file.path && File.exist?(temp_file.path)
      end

      it "downloads and uploads the avatar" do
        result = service.call(avatar_url: avatar_url)

        expect(result).to eq({ key: expected_key, uploaded: true, skipped: false })
      end

      it "calls key_deriver to derive the key" do
        service.call(avatar_url: avatar_url)

        expect(key_deriver).to have_received(:call).with(url: avatar_url)
      end

      it "calls client.download with the URL" do
        service.call(avatar_url: avatar_url)

        expect(client).to have_received(:download).with(url: avatar_url)
      end

      it "calls storage.upload with the temp file" do
        service.call(avatar_url: avatar_url)

        expect(storage).to have_received(:upload).with(
          key: expected_key,
          body: temp_file,
          content_type: content_type
        )
      end
    end

    context "when URL is invalid" do
      it "raises InvalidUrlError for non-HTTP URLs" do
        allow(key_deriver).to receive(:call)
          .with(url: "ftp://example.com/avatar.png")
          .and_raise(AvatarKeyDeriver::InvalidUrlError, "Invalid URL scheme: ftp://example.com/avatar.png")

        expect {
          service.call(avatar_url: "ftp://example.com/avatar.png")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError, /Invalid URL scheme/)
      end

      it "raises InvalidUrlError for non-GitHub URLs" do
        allow(key_deriver).to receive(:call)
          .with(url: "https://example.com/avatar.png")
          .and_raise(AvatarKeyDeriver::InvalidUrlError, "Not a GitHub avatar URL: https://example.com/avatar.png")

        expect {
          service.call(avatar_url: "https://example.com/avatar.png")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError, /Not a GitHub avatar URL/)
      end

      it "raises InvalidUrlError for malformed URLs" do
        allow(key_deriver).to receive(:call)
          .with(url: "not-a-url")
          .and_raise(AvatarKeyDeriver::InvalidUrlError, "Invalid URL")

        expect {
          service.call(avatar_url: "not-a-url")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError)
      end

      it "raises InvalidUrlError when user ID cannot be extracted" do
        allow(key_deriver).to receive(:call)
          .with(url: "https://avatars.githubusercontent.com/some/other/path")
          .and_raise(AvatarKeyDeriver::InvalidUrlError, "Cannot extract user ID from URL")

        expect {
          service.call(avatar_url: "https://avatars.githubusercontent.com/some/other/path")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError, /Cannot extract user ID/)
      end
    end

    context "when download fails" do
      before do
        allow(storage).to receive(:exists?).and_return(false)
      end

      it "raises DownloadError on HTTP error response" do
        allow(client).to receive(:download)
          .and_raise(Github::AvatarsClient::DownloadError, "HTTP error: 404")

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError, /404/)
      end

      it "raises DownloadError on server error" do
        allow(client).to receive(:download)
          .and_raise(Github::AvatarsClient::DownloadError, "HTTP error: 500")

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError, /500/)
      end

      it "raises DownloadError on network timeout" do
        allow(client).to receive(:download)
          .and_raise(Github::AvatarsClient::DownloadError, "Network error downloading image: timeout")

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError, /Network error/)
      end
    end

    context "when file is too large" do
      before do
        allow(storage).to receive(:exists?).and_return(false)
      end

      it "raises FileTooLargeError when Content-Length exceeds limit" do
        allow(client).to receive(:download)
          .and_raise(Github::AvatarsClient::FileTooLargeError, "File size exceeds maximum allowed")

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::FileTooLargeError, /exceeds maximum/)
      end

      it "raises FileTooLargeError during streaming" do
        allow(client).to receive(:download)
          .and_raise(Github::AvatarsClient::FileTooLargeError, "File size exceeded maximum during download")

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::FileTooLargeError, /exceeded maximum/)
      end
    end

    context "key derivation" do
      before do
        allow(storage).to receive(:exists?).and_return(true)
      end

      it "uses key_deriver to extract user ID" do
        allow(key_deriver).to receive(:call)
          .with(url: "https://avatars.githubusercontent.com/u/12345?v=4")
          .and_return("avatars/12345")

        result = service.call(avatar_url: "https://avatars.githubusercontent.com/u/12345?v=4")

        expect(result[:key]).to eq("avatars/12345")
      end

      it "derives key for URL without query parameters" do
        allow(key_deriver).to receive(:call)
          .with(url: "https://avatars.githubusercontent.com/u/67890")
          .and_return("avatars/67890")

        result = service.call(avatar_url: "https://avatars.githubusercontent.com/u/67890")

        expect(result[:key]).to eq("avatars/67890")
      end

      it "handles large user IDs" do
        allow(key_deriver).to receive(:call)
          .with(url: "https://avatars.githubusercontent.com/u/999999999999")
          .and_return("avatars/999999999999")

        result = service.call(avatar_url: "https://avatars.githubusercontent.com/u/999999999999")

        expect(result[:key]).to eq("avatars/999999999999")
      end
    end

    context "temp file cleanup" do
      let(:temp_file) { Tempfile.new(["test", ".tmp"], binmode: true) }

      before do
        temp_file.write(image_data)
        temp_file.rewind

        allow(storage).to receive(:exists?).and_return(false)
        allow(client).to receive(:download)
          .and_return({ temp_file: temp_file, content_type: content_type })
      end

      it "cleans up temp file after successful upload" do
        allow(storage).to receive(:upload).and_return(true)

        service.call(avatar_url: avatar_url)

        expect(temp_file.closed?).to be true
      end

      it "cleans up temp file when upload fails" do
        allow(storage).to receive(:upload).and_raise(StandardError, "Upload failed")

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(StandardError)

        expect(temp_file.closed?).to be true
      end
    end
  end

  describe "dependency injection" do
    it "uses default dependencies when none provided" do
      # Just verify we can create an instance with defaults
      # (they may fail to initialize fully in test environment, so we just check the constructor)
      expect { described_class.new }.not_to raise_error
    end

    it "accepts custom storage" do
      custom_storage = instance_double(AvatarStorage::S3)
      allow(custom_storage).to receive(:exists?).and_return(true)
      allow(key_deriver).to receive(:call).and_return(expected_key)

      custom_service = described_class.new(storage: custom_storage, key_deriver: key_deriver)
      result = custom_service.call(avatar_url: avatar_url)

      expect(result[:skipped]).to be true
    end

    it "accepts custom client" do
      custom_client = instance_double(Github::AvatarsClient)
      temp_file = Tempfile.new(["test", ".tmp"], binmode: true)

      allow(key_deriver).to receive(:call).and_return(expected_key)
      allow(storage).to receive(:exists?).and_return(false)
      allow(storage).to receive(:upload).and_return(true)
      allow(custom_client).to receive(:download)
        .and_return({ temp_file: temp_file, content_type: "image/png" })

      custom_service = described_class.new(storage: storage, client: custom_client, key_deriver: key_deriver)
      custom_service.call(avatar_url: avatar_url)

      expect(custom_client).to have_received(:download)

      temp_file.close unless temp_file.closed?
      temp_file.unlink if temp_file.path && File.exist?(temp_file.path)
    end

    it "accepts custom key_deriver" do
      custom_deriver = instance_double(AvatarKeyDeriver)
      allow(custom_deriver).to receive(:call).and_return("custom/key")
      allow(storage).to receive(:exists?).and_return(true)

      custom_service = described_class.new(storage: storage, key_deriver: custom_deriver)
      result = custom_service.call(avatar_url: avatar_url)

      expect(result[:key]).to eq("custom/key")
    end
  end
end
