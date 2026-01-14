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
    it "retries on DownloadError" do
      expect(described_class).to have_attribute(:retry_on).
        or be_retryable_on(AvatarDownloadAndUploadService::DownloadError)
    end

    it "retries on Aws::S3::Errors::ServiceError" do
      expect(described_class).to have_attribute(:retry_on).
        or be_retryable_on(Aws::S3::Errors::ServiceError)
    end

    it "discards on InvalidUrlError" do
      expect(described_class).to have_attribute(:discard_on).
        or be_discardable_on(AvatarDownloadAndUploadService::InvalidUrlError)
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
