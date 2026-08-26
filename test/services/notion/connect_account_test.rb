require "test_helper"

class Notion::ConnectAccountTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 8, 27, 2)

  test "creates one connection and starts tracking in the user's time zone" do
    user = User.create!(time_zone: "America/Toronto")

    connection = connect(user:)

    assert_equal user, connection.user
    assert_equal "workspace-id", connection.workspace_id
    assert_equal "Example workspace", connection.workspace_name
    assert_equal "bot-id", connection.bot_id
    assert_equal "notion-user-id", connection.owner_user_id
    assert_equal Date.new(2026, 8, 26), connection.tracking_started_on
    assert_equal NOW, connection.authorized_at
  end

  test "reauthorizes the same workspace without resetting the tracking boundary" do
    user = User.create!(time_zone: "UTC")
    original = connect(user:)
    original_tracking_date = original.tracking_started_on
    original_authorized_at = original.authorized_at

    connection = connect(
      user:,
      authorization: authorization.merge(
        bot_id: "rotated-bot-id",
        access_token: "rotated-access-token",
        refresh_token: "rotated-refresh-token"
      ),
      now: NOW + 1.day
    )

    assert_equal original.id, connection.id
    assert_equal 1, NotionConnection.where(user:).count
    assert_equal "rotated-bot-id", connection.bot_id
    assert_equal "rotated-access-token", connection.access_token
    assert_equal "rotated-refresh-token", connection.refresh_token
    assert_equal original_tracking_date, connection.tracking_started_on
    assert_equal original_authorized_at, connection.authorized_at
  end

  test "does not replace an existing connection with a different workspace" do
    user = User.create!
    connection = connect(user:)

    assert_raises Notion::ConnectAccount::Error do
      connect(user:, authorization: authorization.merge(workspace_id: "other-workspace"))
    end

    assert_equal "workspace-id", connection.reload.workspace_id
    assert_equal "access-token", connection.access_token
  end

  test "does not claim a Notion authorization connected to another user" do
    connect(user: User.create!)
    other_user = User.create!

    assert_raises Notion::ConnectAccount::Error do
      connect(user: other_user)
    end

    assert_nil other_user.reload.notion_connection
  end

  private
    def connect(user:, authorization: self.authorization, now: NOW)
      Notion::ConnectAccount.call(user:, authorization:, now:)
    end

    def authorization
      {
        access_token: "access-token",
        refresh_token: "refresh-token",
        bot_id: "bot-id",
        workspace_id: "workspace-id",
        workspace_name: "Example workspace",
        owner_user_id: "notion-user-id"
      }
    end
end
