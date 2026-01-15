# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateGithubUserAvatarKeyService do
  describe "#call" do
    let(:user) { GithubUser.create!(id: 123, login: "testuser") }
    let(:service) { described_class.new }
    let(:avatar_key) { "avatars/123-4" }

    it "updates the user's avatar_key" do
      service.call(user_id: user.id, avatar_key: avatar_key)

      expect(user.reload.avatar_key).to eq(avatar_key)
    end

    it "returns the updated user" do
      result = service.call(user_id: user.id, avatar_key: avatar_key)

      expect(result).to eq(user.reload)
      expect(result.avatar_key).to eq(avatar_key)
    end

    it "raises RecordNotFound for non-existent user" do
      expect {
        service.call(user_id: 99999, avatar_key: avatar_key)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "logs the update" do
      allow(Rails.logger).to receive(:info)

      service.call(user_id: user.id, avatar_key: avatar_key)

      expect(Rails.logger).to have_received(:info).with(
        "UpdateGithubUserAvatarKeyService: Updated avatar_key for user #{user.id} - key: #{avatar_key}"
      )
    end
  end
end
