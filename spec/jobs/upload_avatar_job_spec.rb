# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadAvatarJob, type: :job do
  let(:avatar_url) { "https://avatars.githubusercontent.com/u/178611968?v=4" }

  describe "#perform" do
    it "calls AvatarDownloadAndUploadService with the avatar URL" do
      service = instance_double(AvatarDownloadAndUploadService)
      allow(AvatarDownloadAndUploadService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_return({ key: "avatars/178611968", uploaded: true, skipped: false })

      described_class.new.perform(avatar_url)

      expect(service).to have_received(:call).with(avatar_url: avatar_url)
    end
  end

  describe "retry behavior" do
    it "has retry configured for DownloadError" do
      retry_handlers = described_class.rescue_handlers.select do |handler|
        handler[0] == AvatarDownloadAndUploadService::DownloadError.name
      end

      expect(retry_handlers).not_to be_empty
    end

    it "has retry configured for Aws::S3::Errors::ServiceError" do
      retry_handlers = described_class.rescue_handlers.select do |handler|
        handler[0] == "Aws::S3::Errors::ServiceError"
      end

      expect(retry_handlers).not_to be_empty
    end

    it "discards on InvalidUrlError" do
      service = instance_double(AvatarDownloadAndUploadService)
      allow(AvatarDownloadAndUploadService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(AvatarDownloadAndUploadService::InvalidUrlError, "Invalid URL")

      expect {
        described_class.perform_now(avatar_url)
      }.not_to have_enqueued_job(described_class)
    end

    it "discards on FileTooLargeError" do
      service = instance_double(AvatarDownloadAndUploadService)
      allow(AvatarDownloadAndUploadService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(AvatarDownloadAndUploadService::FileTooLargeError, "File too large")

      expect {
        described_class.perform_now(avatar_url)
      }.not_to have_enqueued_job(described_class)
    end
  end

  describe "job enqueueing" do
    it "can be enqueued with an avatar URL" do
      expect {
        described_class.perform_later(avatar_url)
      }.to have_enqueued_job(described_class).with(avatar_url)
    end
  end
end
