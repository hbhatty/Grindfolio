require "test_helper"

class NotionActivityUpdatesControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    Rails.cache.clear
    @sync_service = NotionActivityUpdatesController.sync_service
  end

  teardown do
    Current.reset
    Rails.cache.clear
    NotionActivityUpdatesController.sync_service = @sync_service
  end

  test "requires authentication and the current user's Notion connection" do
    post notion_activity_update_path

    assert_response :see_other
    assert_redirected_to sign_in_path

    user = create_verified_user(email_address: "unconnected@example.com")
    sign_in_as(user)
    post notion_activity_update_path

    assert_response :see_other
    assert_redirected_to root_path
    assert_equal "Connect Notion before updating activity.", flash[:alert]
  end

  test "synchronizes only the current user's connection" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user:)
    other_connection = create_connection(
      user: create_verified_user(email_address: "other@example.com")
    )
    received = nil
    NotionActivityUpdatesController.sync_service = lambda do |connection:|
      received = connection
      1
    end
    sign_in_as(user)

    post notion_activity_update_path

    assert_response :see_other
    assert_redirected_to root_path
    assert_equal connection, received
    assert_not_equal other_connection, received
    assert_equal "Notion activity update completed.", flash[:notice]
  end

  test "prevents another provider request during the connection cooldown" do
    user = create_verified_user(email_address: "developer@example.com")
    create_connection(user:)
    calls = 0
    NotionActivityUpdatesController.sync_service = lambda do |connection:|
      calls += 1
      0
    end
    sign_in_as(user)

    post notion_activity_update_path
    post notion_activity_update_path

    assert_equal 1, calls
    assert_response :see_other
    assert_equal "Notion activity was recently updated. Please wait before updating again.", flash[:notice]
  end

  test "keeps provider and reauthorization failures scoped to Notion" do
    user = create_verified_user(email_address: "developer@example.com")
    create_connection(user:)
    sign_in_as(user)
    NotionActivityUpdatesController.sync_service = lambda do |connection:|
      raise Notion::SyncApplications::ReauthorizationRequired
    end

    post notion_activity_update_path

    assert_response :see_other
    assert_equal "Reauthorize Notion before updating activity. Your saved activity is unchanged.", flash[:alert]
  end

  private
    def create_connection(user:)
      user.create_notion_connection!(
        workspace_id: "workspace-#{user.id}",
        workspace_name: "Example workspace",
        bot_id: "bot-#{user.id}",
        owner_user_id: "owner-#{user.id}",
        access_token: "access-token",
        refresh_token: "refresh-token",
        tracking_started_on: Date.new(2026, 8, 26),
        authorized_at: Time.utc(2026, 8, 26, 16)
      )
    end

    def create_verified_user(email_address:)
      user = User.create!
      user.create_password_credential!(
        email_address:,
        password: PASSWORD,
        password_confirmation: PASSWORD,
        email_verified_at: Time.current
      )
      user
    end

    def sign_in_as(user)
      post sign_in_path,
        params: {
          session: {
            email_address: user.password_credential.email_address,
            password: PASSWORD
          }
        }
      assert_response :see_other
    end
end
