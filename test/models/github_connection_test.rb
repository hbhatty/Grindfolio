require "test_helper"

class GithubConnectionTest < ActiveSupport::TestCase
  test "belongs to a GitHub identity and starts pending" do
    user = User.create!
    identity = user.external_identities.create!(provider: "github", provider_uid: "github-id")
    connection = identity.create_github_connection!(connection_attributes)

    assert_equal identity, connection.external_identity
    assert_equal user, connection.user
    assert_predicate connection, :sync_status_pending?
  end

  test "encrypts OAuth credentials in the raw database columns" do
    identity = User.create!.external_identities.create!(provider: "github", provider_uid: "github-id")
    connection = identity.create_github_connection!(connection_attributes)

    raw_columns = GithubConnection.connection.select_one(<<~SQL)
      SELECT access_token, refresh_token
      FROM github_connections
      WHERE id = #{connection.id}
    SQL

    assert_equal "plain-access-token", connection.reload.access_token
    assert_equal "plain-refresh-token", connection.refresh_token
    assert_not_equal "plain-access-token", raw_columns.fetch("access_token")
    assert_not_equal "plain-refresh-token", raw_columns.fetch("refresh_token")
    assert_not_includes raw_columns.fetch("access_token"), "plain-access-token"
    assert_not_includes raw_columns.fetch("refresh_token"), "plain-refresh-token"
  end

  test "rejects a connection for a non-GitHub identity" do
    identity = User.create!.external_identities.create!(
      provider: "google",
      provider_uid: "google-id"
    )
    connection = identity.build_github_connection(connection_attributes)

    assert_not connection.valid?
    assert_includes connection.errors[:external_identity], "must be a GitHub identity"
  end

  test "allows only one connection for a GitHub identity" do
    identity = User.create!.external_identities.create!(provider: "github", provider_uid: "github-id")
    identity.create_github_connection!(connection_attributes)
    duplicate = GithubConnection.new(
      external_identity: identity,
      **connection_attributes(tracking_started_on: Date.new(2026, 8, 23))
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:external_identity_id], "has already been taken"
  end

  test "rejects an unsupported synchronization status" do
    identity = User.create!.external_identities.create!(provider: "github", provider_uid: "github-id")
    connection = identity.build_github_connection(
      **connection_attributes,
      sync_status: "unknown"
    )

    assert_not connection.valid?
    assert_includes connection.errors[:sync_status], "is not included in the list"
  end
  test "requires renewable OAuth credentials and the access-token expiry" do
    identity = User.create!.external_identities.create!(provider: "github", provider_uid: "github-id")

    %i[access_token refresh_token access_token_expires_at].each do |attribute|
      connection = identity.build_github_connection(connection_attributes.merge(attribute => nil))

      assert_not connection.valid?
      assert_includes connection.errors[attribute], "can't be blank"
    end
  end

  private
    def connection_attributes(tracking_started_on: Date.new(2026, 8, 22))
      {
        tracking_started_on:,
        access_token: "plain-access-token",
        refresh_token: "plain-refresh-token",
        access_token_expires_at: Time.utc(2026, 8, 22, 20)
      }
    end
end
