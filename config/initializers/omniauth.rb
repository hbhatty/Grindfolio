github_client_id = Rails.application.credentials.dig(:github_app, :client_id)
github_client_secret = Rails.application.credentials.dig(:github_app, :client_secret)

if Rails.env.test?
  github_client_id ||= "test-github-app-client-id"
  github_client_secret ||= "test-github-app-client-secret"
end

if github_client_id.blank? || github_client_secret.blank?
  raise "Missing GitHub App client credentials for #{Rails.env}"
end

Rails.application.config.x.github.authorization_app = :github_app
Rails.application.config.x.github.oauth_scope = nil

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github,
    github_client_id,
    github_client_secret
end
