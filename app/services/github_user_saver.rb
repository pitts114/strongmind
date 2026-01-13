class GithubUserSaver
  def call(user_data:)
    attributes = map_user_attributes(user_data)
    user = GithubUser.find_or_initialize_by(id: attributes[:id])
    user.update!(attributes.except(:id))
    user
  end

  private

  def map_user_attributes(data)
    {
      id: data["id"],
      login: data["login"],
      node_id: data["node_id"],
      avatar_url: data["avatar_url"],
      gravatar_id: data["gravatar_id"],
      url: data["url"],
      html_url: data["html_url"],
      followers_url: data["followers_url"],
      following_url: data["following_url"],
      gists_url: data["gists_url"],
      starred_url: data["starred_url"],
      subscriptions_url: data["subscriptions_url"],
      organizations_url: data["organizations_url"],
      repos_url: data["repos_url"],
      events_url: data["events_url"],
      received_events_url: data["received_events_url"],
      type: data["type"],
      user_view_type: data["user_view_type"],
      site_admin: data["site_admin"],
      name: data["name"],
      company: data["company"],
      blog: data["blog"],
      location: data["location"],
      email: data["email"],
      hireable: data["hireable"],
      bio: data["bio"],
      twitter_username: data["twitter_username"],
      public_repos: data["public_repos"],
      public_gists: data["public_gists"],
      followers: data["followers"],
      following: data["following"],
      github_created_at: data["created_at"],
      github_updated_at: data["updated_at"]
    }
  end
end
