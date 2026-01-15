# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessAvatarJob, type: :job do
  let(:user_id) { 178611968 }
  let(:avatar_url) { "https://avatars.githubusercontent.com/u/178611968?v=4" }

  describe "#perform" do
    it "calls ProcessAvatarService with user_id and avatar_url" do
      service = instance_double(ProcessAvatarService)
      allow(ProcessAvatarService).to receive(:new).and_return(service)
      allow(service).to receive(:call)

      described_class.new.perform(user_id, avatar_url)

      expect(service).to have_received(:call).with(user_id: user_id, avatar_url: avatar_url)
    end
  end

  describe "retry behavior" do
    it "has retry configured for DownloadError" do
      retry_handlers = described_class.rescue_handlers.select do |handler|
        handler[0] == AvatarDownloadAndStoreService::DownloadError.name
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
      service = instance_double(ProcessAvatarService)
      allow(ProcessAvatarService).to receive(:new).and_return(service)
      allow(service).to receive(:call)
        .and_raise(AvatarDownloadAndStoreService::InvalidUrlError, "Invalid URL")

      expect {
        described_class.perform_now(user_id, avatar_url)
      }.not_to have_enqueued_job(described_class)
    end

    it "discards on FileTooLargeError" do
      service = instance_double(ProcessAvatarService)
      allow(ProcessAvatarService).to receive(:new).and_return(service)
      allow(service).to receive(:call)
        .and_raise(AvatarDownloadAndStoreService::FileTooLargeError, "File too large")

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
