class GithubOrganizationSaver
  def call(organization_data:)
    attributes = map_organization_attributes(organization_data)
    organization = GithubOrganization.find_or_initialize_by(id: attributes[:id])
    organization.update!(attributes.except(:id))
    organization
  end

  private

  def map_organization_attributes(data)
    {
      id: data["id"],
      login: data["login"],
      node_id: data["node_id"],
      avatar_url: data["avatar_url"],
      url: data["url"],
      html_url: data["html_url"],
      repos_url: data["repos_url"],
      events_url: data["events_url"],
      hooks_url: data["hooks_url"],
      issues_url: data["issues_url"],
      members_url: data["members_url"],
      public_members_url: data["public_members_url"],
      type: data["type"],
      name: data["name"],
      company: data["company"],
      blog: data["blog"],
      location: data["location"],
      email: data["email"],
      description: data["description"],
      twitter_username: data["twitter_username"],
      is_verified: data["is_verified"],
      has_organization_projects: data["has_organization_projects"],
      has_repository_projects: data["has_repository_projects"],
      public_repos: data["public_repos"],
      public_gists: data["public_gists"],
      followers: data["followers"],
      following: data["following"],
      github_created_at: data["created_at"],
      github_updated_at: data["updated_at"],
      archived_at: data["archived_at"]
    }
  end
end
