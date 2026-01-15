# frozen_string_literal: true

class ProcessAvatarService
  def initialize(
    download_and_store_service: AvatarDownloadAndStoreService.new,
    update_avatar_key_service: UpdateGithubUserAvatarKeyService.new
  )
    @download_and_store_service = download_and_store_service
    @update_avatar_key_service = update_avatar_key_service
  end

  # Downloads/stores avatar and updates user's avatar_key
  # @param user_id [Integer] GitHub user ID
  # @param avatar_url [String] GitHub avatar URL
  # @return [GithubUser, nil] Updated user, or nil if no update was needed
  def call(user_id:, avatar_url:)
    Rails.logger.info("ProcessAvatarService: Processing avatar - user_id: #{user_id}, url: #{avatar_url}")

    result = download_and_store_service.call(avatar_url: avatar_url)

    if result[:uploaded] || result[:skipped]
      user = update_avatar_key_service.call(user_id: user_id, avatar_key: result[:key])
      Rails.logger.info("ProcessAvatarService: Avatar processed successfully - user_id: #{user_id}, key: #{result[:key]}")
      user
    else
      Rails.logger.info("ProcessAvatarService: No avatar update needed - user_id: #{user_id}")
      nil
    end
  end

  private

  attr_reader :download_and_store_service, :update_avatar_key_service
end
