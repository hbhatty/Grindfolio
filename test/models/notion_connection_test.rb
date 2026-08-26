require "test_helper"

class NotionConnectionTest < ActiveSupport::TestCase
  test "belongs to one user and stores the provider authorization identity" do
    user = User.create!
    connection = user.create_notion_connection!(connection_attributes)

    assert_equal user, connection.user
    assert_equal "workspace-id", connection.workspace_id
    assert_equal "bot-id", connection.bot_id
    assert_equal "owner-user-id", connection.owner_user_id
  end

  test "encrypts renewable OAuth credentials in the raw database columns" do
    connection = User.create!.create_notion_connection!(connection_attributes)

    raw_columns = NotionConnection.connection.select_one(<<~SQL)
      SELECT access_token, refresh_token
      FROM notion_connections
      WHERE id = #{connection.id}
    SQL

    assert_equal "plain-access-token", connection.reload.access_token
    assert_equal "plain-refresh-token", connection.refresh_token
    assert_not_equal "plain-access-token", raw_columns.fetch("access_token")
    assert_not_equal "plain-refresh-token", raw_columns.fetch("refresh_token")
    assert_not_includes raw_columns.fetch("access_token"), "plain-access-token"
    assert_not_includes raw_columns.fetch("refresh_token"), "plain-refresh-token"
  end

  test "allows one Notion connection per user" do
    user = User.create!
    user.create_notion_connection!(connection_attributes)
    duplicate = NotionConnection.new(user:, **connection_attributes(bot_id: "another-bot-id"))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "allows one Grindfolio connection per Notion authorization" do
    User.create!.create_notion_connection!(connection_attributes)
    duplicate = User.create!.build_notion_connection(connection_attributes)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:bot_id], "has already been taken"
  end

  test "requires provider identity, renewable credentials, and tracking timestamps" do
    user = User.create!

    %i[workspace_id bot_id access_token refresh_token tracking_started_on authorized_at].each do |attribute|
      connection = user.build_notion_connection(connection_attributes.merge(attribute => nil))

      assert_not connection.valid?
      assert_includes connection.errors[attribute], "can't be blank"
    end
  end

  private
    def connection_attributes(bot_id: "bot-id")
      {
        workspace_id: "workspace-id",
        workspace_name: "Example workspace",
        bot_id:,
        owner_user_id: "owner-user-id",
        access_token: "plain-access-token",
        refresh_token: "plain-refresh-token",
        tracking_started_on: Date.new(2026, 8, 26),
        authorized_at: Time.utc(2026, 8, 26, 16, 30)
      }
    end
end
