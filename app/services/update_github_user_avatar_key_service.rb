# frozen_string_literal: true

class UpdateGithubUserAvatarKeyService
  # Updates a GitHub user's avatar_key attribute
  # @param user_id [Integer] GitHub user ID
  # @param avatar_key [String] S3 key for the avatar
  # @return [GithubUser] Updated user record
  # @raise [ActiveRecord::RecordNotFound] if user doesn't exist
  def call(user_id:, avatar_key:)
    user = GithubUser.find(user_id)
    user.update!(avatar_key: avatar_key)
    Rails.logger.info("UpdateGithubUserAvatarKeyService: Updated avatar_key for user #{user_id} - key: #{avatar_key}")
    user
  end
end
