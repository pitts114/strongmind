# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadAvatarJob, type: :job do
  let(:user_id) { 178611968 }
  let(:avatar_url) { "https://avatars.githubusercontent.com/u/178611968?v=4" }
  let(:expected_key) { "avatars/178611968-4" }

  describe "#perform" do
    let!(:user) { GithubUser.create!(id: user_id, login: "testuser") }

    it "calls AvatarDownloadAndUploadService with the avatar URL" do
      service = instance_double(AvatarDownloadAndUploadService)
      allow(AvatarDownloadAndUploadService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_return({ key: expected_key, uploaded: true, skipped: false })

      described_class.new.perform(user_id, avatar_url)

      expect(service).to have_received(:call).with(avatar_url: avatar_url)
    end

    it "updates user avatar_key when upload succeeds" do
      service = instance_double(AvatarDownloadAndUploadService)
      allow(AvatarDownloadAndUploadService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_return({ key: expected_key, uploaded: true, skipped: false })

      described_class.new.perform(user_id, avatar_url)

      expect(user.reload.avatar_key).to eq(expected_key)
    end

    it "updates user avatar_key when upload is skipped (already exists)" do
      service = instance_double(AvatarDownloadAndUploadService)
      allow(AvatarDownloadAndUploadService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_return({ key: expected_key, uploaded: false, skipped: true })

      described_class.new.perform(user_id, avatar_url)

      expect(user.reload.avatar_key).to eq(expected_key)
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
        described_class.perform_now(user_id, avatar_url)
      }.not_to have_enqueued_job(described_class)
    end

    it "discards on FileTooLargeError" do
      service = instance_double(AvatarDownloadAndUploadService)
      allow(AvatarDownloadAndUploadService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(AvatarDownloadAndUploadService::FileTooLargeError, "File too large")

      expect {
        described_class.perform_now(user_id, avatar_url)
      }.not_to have_enqueued_job(described_class)
    end
  end

  describe "job enqueueing" do
    it "can be enqueued with user_id and avatar_url" do
      expect {
        described_class.perform_later(user_id, avatar_url)
      }.to have_enqueued_job(described_class).with(user_id, avatar_url)
    end
  end
end
