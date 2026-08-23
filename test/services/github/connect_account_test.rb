require "test_helper"

class Github::ConnectAccountTest < ActiveSupport::TestCase
  test "atomically creates a data-only identity and pending connection" do
    user = User.create!

    connection = assert_difference -> { ExternalIdentity.count } => 1,
      -> { GithubConnection.count } => 1 do
      connect(user:, tracking_date: Date.new(2026, 8, 22))
    end

    identity = connection.external_identity
    assert_equal user, identity.user
    assert_equal "github", identity.provider
    assert_equal "42", identity.provider_uid
    assert_equal "octocat", identity.provider_username
    assert_equal "octocat@example.com", identity.provider_email
    assert_equal "https://example.com/octocat.png", identity.profile_image_url
    assert_nil identity.login_enabled_at
    assert_equal Date.new(2026, 8, 22), connection.tracking_started_on
    assert_predicate connection, :sync_status_pending?
    assert_equal "access-token", connection.access_token
    assert_equal "refresh-token", connection.refresh_token
    assert_equal Time.utc(2026, 8, 22, 20), connection.access_token_expires_at
    assert_nil connection.refresh_token_expires_at
    assert_empty connection.daily_contributions
  end

  test "defaults the tracking date to the user's selected time zone" do
    travel_to Time.utc(2026, 8, 23, 0, 6) do
      user = User.create!(time_zone: "America/Toronto")

      connection = Github::ConnectAccount.new(user:, authorization: authorization).call

      assert_equal Date.new(2026, 8, 22), connection.tracking_started_on
    end
  end

  test "defaults the tracking date to UTC when the user has no selected time zone" do
    travel_to Time.utc(2026, 8, 23, 0, 6) do
      user = User.create!

      connection = Github::ConnectAccount.new(user:, authorization: authorization).call

      assert_equal Date.new(2026, 8, 23), connection.tracking_started_on
    end
  end

  test "reauthorization updates metadata and credentials without duplicating or resetting tracking" do
    user = User.create!
    original = connect(user:, tracking_date: Date.new(2026, 8, 20))
    original.update!(
      sync_status: "ready",
      refresh_token_expires_at: Time.utc(2027, 2, 20)
    )

    updated_authorization = authorization(
      nickname: "monalisa",
      access_token: "new-access-token",
      refresh_token: "new-refresh-token",
      expires_at: Time.utc(2026, 8, 23, 20)
    )

    connection = assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        connect(
          user:,
          authorization: updated_authorization,
          tracking_date: Date.new(2026, 8, 23)
        )
      end
    end

    assert_equal original.id, connection.id
    assert_equal Date.new(2026, 8, 20), connection.tracking_started_on
    assert_equal "monalisa", connection.external_identity.provider_username
    assert_equal "new-access-token", connection.access_token
    assert_equal "new-refresh-token", connection.refresh_token
    assert_equal Time.utc(2026, 8, 23, 20), connection.access_token_expires_at
    assert_nil connection.refresh_token_expires_at
    assert_predicate connection, :sync_status_ready?
    assert_nil connection.last_sync_error
  end

  test "reauthorization does not erase an existing synchronization error" do
    user = User.create!
    original = connect(user:)
    original.update!(sync_status: "error", last_sync_error: "GitHub was temporarily unavailable")

    connection = connect(
      user:,
      authorization: authorization(
        access_token: "new-access-token",
        refresh_token: "new-refresh-token"
      )
    )

    assert_predicate connection, :sync_status_error?
    assert_equal "GitHub was temporarily unavailable", connection.last_sync_error
    assert_equal "new-access-token", connection.access_token
  end

  test "reauthorization replaces unreadable old ciphertext without resetting the connection" do
    user = User.create!
    original = connect(user:, tracking_date: Date.new(2026, 8, 20))
    original.update!(sync_status: "ready")
    write_unreadable_credentials(original)

    connection = connect(
      user:,
      authorization: authorization(
        access_token: "replacement-access-token",
        refresh_token: "replacement-refresh-token"
      ),
      tracking_date: Date.new(2026, 8, 23)
    )

    assert_equal original.id, connection.id
    assert_equal Date.new(2026, 8, 20), connection.tracking_started_on
    assert_predicate connection, :sync_status_ready?
    assert_equal "replacement-access-token", connection.access_token
    assert_equal "replacement-refresh-token", connection.refresh_token
  end

  test "rejects a GitHub identity claimed by another Gridfolio user" do
    owner = User.create!
    attacker = User.create!
    original = connect(user: owner)

    assert_no_changes -> { original.external_identity.reload.attributes } do
      assert_no_difference -> { GithubConnection.count } do
        assert_raises Github::ConnectAccount::IdentityAlreadyConnected do
          connect(user: attacker)
        end
      end
    end

    assert_empty attacker.external_identities
  end

  test "does not silently replace a different GitHub account for the same user" do
    user = User.create!
    original = connect(user:)

    assert_raises Github::ConnectAccount::DifferentIdentityAlreadyConnected do
      connect(user:, authorization: authorization(uid: "84"))
    end

    assert_equal "42", original.external_identity.reload.provider_uid
    assert_equal 1, user.external_identities.github.count
  end

  test "saves nothing when renewable authorization credentials are incomplete" do
    user = User.create!
    incomplete_authorization = authorization(refresh_token: nil)

    assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        assert_raises Github::ConnectAccount::Error do
          connect(user:, authorization: incomplete_authorization)
        end
      end
    end
  end

  test "rolls back identity creation if the connection cannot be saved" do
    user = User.create!

    assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        assert_raises Github::ConnectAccount::Error do
          connect(user:, tracking_date: "not-a-date")
        end
      end
    end
  end

  private
    def write_unreadable_credentials(connection)
      quoted_value = GithubConnection.connection.quote("not-valid-encrypted-data")
      GithubConnection.connection.execute(<<~SQL)
        UPDATE github_connections
        SET access_token = #{quoted_value}, refresh_token = #{quoted_value}
        WHERE id = #{connection.id}
      SQL
    end

    def connect(user:, authorization: authorization(), tracking_date: Date.new(2026, 8, 22))
      Github::ConnectAccount.new(user:, authorization:, tracking_date:).call
    end

    def authorization(
      uid: "42",
      nickname: "octocat",
      access_token: "access-token",
      refresh_token: "refresh-token",
      expires_at: Time.utc(2026, 8, 22, 20)
    )
      OmniAuth::AuthHash.new(
        uid:,
        info: {
          nickname:,
          email: "octocat@example.com",
          image: "https://example.com/octocat.png"
        },
        credentials: {
          token: access_token,
          refresh_token:,
          expires: true,
          expires_at: expires_at&.to_i
        }
      )
    end
end
