require "test_helper"

class NotionApplicationStatusChangeTest < ActiveSupport::TestCase
  setup do
    connection = User.create!.create_notion_connection!(
      workspace_id: "workspace-id",
      bot_id: "bot-id",
      access_token: "access-token",
      refresh_token: "refresh-token",
      tracking_started_on: Date.new(2026, 8, 20),
      authorized_at: Time.utc(2026, 8, 20, 16)
    )
    @application = connection.applications.create!(
      provider_page_id: "provider-page-id",
      applied_on: Date.new(2026, 8, 20),
      company_name: "IBM",
      role: "Software Developer",
      current_status: "Rejected",
      provider_last_edited_at: Time.utc(2026, 8, 25, 18)
    )
  end

  test "records when Grindfolio detected a status transition" do
    change = @application.status_changes.create!(
      from_status: "Applied",
      to_status: "Rejected",
      detected_on: Date.new(2026, 8, 25),
      detected_at: Time.utc(2026, 8, 25, 20)
    )

    assert_equal @application, change.notion_application
    assert_equal "Applied", change.from_status
    assert_equal "Rejected", change.to_status
    assert_equal Date.new(2026, 8, 25), change.detected_on
  end

  test "requires a real transition and detection time" do
    change = @application.status_changes.build(
      from_status: "Applied",
      to_status: "Applied"
    )

    assert_not change.valid?
    assert_includes change.errors[:to_status], "must differ from the previous status"
    assert_includes change.errors[:detected_on], "can't be blank"
    assert_includes change.errors[:detected_at], "can't be blank"
  end

  test "is deleted with its application" do
    @application.status_changes.create!(
      from_status: "Applied",
      to_status: "Rejected",
      detected_on: Date.new(2026, 8, 25),
      detected_at: Time.utc(2026, 8, 25, 20)
    )

    assert_difference -> { NotionApplicationStatusChange.count }, -1 do
      @application.destroy!
    end
  end
end
