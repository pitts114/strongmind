# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessAvatarService do
  let(:download_and_store_service) { instance_double(AvatarDownloadAndStoreService) }
  let(:update_avatar_key_service) { instance_double(UpdateGithubUserAvatarKeyService) }
  let(:service) do
    described_class.new(
      download_and_store_service: download_and_store_service,
      update_avatar_key_service: update_avatar_key_service
    )
  end

  let(:user_id) { 123 }
  let(:avatar_url) { "https://avatars.githubusercontent.com/u/123?v=4" }
  let(:avatar_key) { "avatars/123-4" }

  describe "#call" do
    context "when avatar is uploaded" do
      let(:user) { instance_double(GithubUser, id: user_id) }

      before do
        allow(download_and_store_service).to receive(:call)
          .with(avatar_url: avatar_url)
          .and_return({ key: avatar_key, uploaded: true, skipped: false })
        allow(update_avatar_key_service).to receive(:call)
          .with(user_id: user_id, avatar_key: avatar_key)
          .and_return(user)
      end

      it "downloads/stores the avatar" do
        service.call(user_id: user_id, avatar_url: avatar_url)

        expect(download_and_store_service).to have_received(:call).with(avatar_url: avatar_url)
      end

      it "updates the user's avatar_key" do
        service.call(user_id: user_id, avatar_url: avatar_url)

        expect(update_avatar_key_service).to have_received(:call).with(user_id: user_id, avatar_key: avatar_key)
      end

      it "returns the updated user" do
        result = service.call(user_id: user_id, avatar_url: avatar_url)

        expect(result).to eq(user)
      end
    end

    context "when avatar is skipped (already exists)" do
      let(:user) { instance_double(GithubUser, id: user_id) }

      before do
        allow(download_and_store_service).to receive(:call)
          .with(avatar_url: avatar_url)
          .and_return({ key: avatar_key, uploaded: false, skipped: true })
        allow(update_avatar_key_service).to receive(:call)
          .with(user_id: user_id, avatar_key: avatar_key)
          .and_return(user)
      end

      it "still updates the user's avatar_key" do
        service.call(user_id: user_id, avatar_url: avatar_url)

        expect(update_avatar_key_service).to have_received(:call).with(user_id: user_id, avatar_key: avatar_key)
      end

      it "returns the updated user" do
        result = service.call(user_id: user_id, avatar_url: avatar_url)

        expect(result).to eq(user)
      end
    end

    context "when download/store raises InvalidUrlError" do
      before do
        allow(download_and_store_service).to receive(:call)
          .and_raise(AvatarDownloadAndStoreService::InvalidUrlError, "Invalid URL")
        allow(update_avatar_key_service).to receive(:call)
      end

      it "propagates the error" do
        expect {
          service.call(user_id: user_id, avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndStoreService::InvalidUrlError)
      end

      it "does not update the user's avatar_key" do
        expect {
          service.call(user_id: user_id, avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndStoreService::InvalidUrlError)

        expect(update_avatar_key_service).not_to have_received(:call)
      end
    end

    context "when download/store raises DownloadError" do
      before do
        allow(download_and_store_service).to receive(:call)
          .and_raise(AvatarDownloadAndStoreService::DownloadError, "Network error")
      end

      it "propagates the error" do
        expect {
          service.call(user_id: user_id, avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndStoreService::DownloadError)
      end
    end

    context "when download/store raises FileTooLargeError" do
      before do
        allow(download_and_store_service).to receive(:call)
          .and_raise(AvatarDownloadAndStoreService::FileTooLargeError, "File too large")
      end

      it "propagates the error" do
        expect {
          service.call(user_id: user_id, avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndStoreService::FileTooLargeError)
      end
    end
  end

  describe "dependency injection" do
    it "uses default dependencies when none provided" do
      expect { described_class.new }.not_to raise_error
    end
  end
end
