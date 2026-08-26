require "test_helper"

class NotionApplicationTest < ActiveSupport::TestCase
  setup do
    @connection = User.create!.create_notion_connection!(
      workspace_id: "workspace-id",
      workspace_name: "Example workspace",
      bot_id: "bot-id",
      owner_user_id: "owner-user-id",
      access_token: "access-token",
      refresh_token: "refresh-token",
      tracking_started_on: Date.new(2026, 8, 26),
      authorized_at: Time.utc(2026, 8, 26, 16)
    )
  end

  test "stores only mapped application detail inside the tracking window" do
    application = @connection.applications.create!(application_attributes)

    assert_equal @connection, application.notion_connection
    assert_equal Date.new(2026, 8, 26), application.applied_on
    assert_equal "Example Company", application.company_name
    assert_equal "Software Engineering Intern", application.role
    assert_equal "Applied", application.current_status
  end

  test "uniquely identifies a provider page inside one connection" do
    @connection.applications.create!(application_attributes)
    duplicate = @connection.applications.build(application_attributes)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:provider_page_id], "has already been taken"
  end

  test "rejects activity before Notion tracking began" do
    application = @connection.applications.build(
      application_attributes(applied_on: Date.new(2026, 8, 25))
    )

    assert_not application.valid?
    assert_includes application.errors[:applied_on], "cannot precede Notion tracking"
  end

  test "is deleted with its provider connection" do
    @connection.applications.create!(application_attributes)

    assert_difference -> { NotionApplication.count }, -1 do
      @connection.destroy!
    end
  end

  private
    def application_attributes(applied_on: Date.new(2026, 8, 26))
      {
        provider_page_id: "provider-page-id",
        applied_on:,
        company_name: "Example Company",
        role: "Software Engineering Intern",
        current_status: "Applied",
        provider_last_edited_at: Time.utc(2026, 8, 26, 18)
      }
    end
end
