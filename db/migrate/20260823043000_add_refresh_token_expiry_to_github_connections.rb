class AddRefreshTokenExpiryToGithubConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :github_connections, :refresh_token_expires_at, :datetime
  end
end
