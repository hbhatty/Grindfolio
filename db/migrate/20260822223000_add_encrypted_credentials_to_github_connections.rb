class AddEncryptedCredentialsToGithubConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :github_connections, :access_token, :text, null: false
    add_column :github_connections, :refresh_token, :text, null: false
    add_column :github_connections, :access_token_expires_at, :datetime, null: false
  end
end
