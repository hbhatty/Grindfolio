require "test_helper"

class ActivityUpdatesControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  class NotionClient
    attr_accessor :error

    def data_sources
      raise error if error

      [ { "object" => "data_source", "id" => "source" } ]
    end

    def data_source(*)
      {
        "object" => "data_source", "id" => "source",
        "properties" => Notion::DiscoverTemplate::EXPECTED_PROPERTIES.to_h do |key, (name, type)|
          [ name, { "id" => key.to_s, "type" => type } ]
        end
      }
    end

    def applications(**)
      [ {
        "object" => "page", "id" => "historical", "last_edited_time" => Time.current.iso8601,
        "properties" => {
          "Company Name" => { "id" => "company_name", "type" => "title", "title" => [ { "plain_text" => "Earlier Company" } ] },
          "Application Date" => {
            "id" => "application_date", "type" => "date",
            "date" => { "start" => Date.yesterday.iso8601, "end" => nil, "time_zone" => nil }
          },
          "Role / Position" => { "id" => "role", "type" => "rich_text", "rich_text" => [] },
          "Application Status" => { "id" => "status", "type" => "status", "status" => { "name" => "Applied" } }
        }
      } ]
    end
  end

  setup do
    Current.reset
    Rails.cache.clear
    clear_enqueued_jobs
    @user = User.create!
    @user.create_password_credential!(
      email_address: "bulk@example.com", password: PASSWORD,
      password_confirmation: PASSWORD, email_verified_at: Time.current
    )
  end

  teardown do
    Current.reset
    Rails.cache.clear
    clear_enqueued_jobs
  end

  test "requires authentication and rejects a missing CSRF token" do
    assert_no_enqueued_jobs { post activity_update_path }
    assert_redirected_to sign_in_path

    sign_in
    previous_setting = ActivityUpdatesController.allow_forgery_protection
    ActivityUpdatesController.allow_forgery_protection = true
    assert_no_enqueued_jobs { post activity_update_path }
    assert_response :unprocessable_entity
  ensure
    ActivityUpdatesController.allow_forgery_protection = previous_setting unless previous_setting.nil?
  end

  test "updates only the owner and shares cooldowns with individual actions without importing history" do
    github, leetcode, notion = connect_providers(@user)
    other_github, other_leetcode, other_notion = connect_providers(User.create!)
    cached = cache_application(notion)
    other_cached = cache_application(other_notion)
    sign_in

    with_provider_responses do |calendar, client|
      assert_enqueued_with job: Github::SyncContributionsJob, args: [ github.id ] do
        post activity_update_path, params: { user_id: other_notion.user_id }
      end
      assert_redirected_to root_path
      assert_equal 4, leetcode.daily_activities.find_by!(activity_date: Date.current).submission_count
      assert_not NotionApplication.exists?(cached.id)
      assert_not notion.applications.exists?(provider_page_id: "historical")
      assert_predicate github.reload, :sync_status_queued?
      assert_predicate other_github.reload, :sync_status_pending?
      assert_nil other_leetcode.reload.last_synced_at
      assert_nil other_notion.reload.last_synced_at
      assert NotionApplication.exists?(other_cached.id)

      github.update!(sync_status: "ready")
      calendar.define_singleton_method(:call) { raise "cooldown contacted LeetCode" }
      client.error = Notion::ApiClient::Error.new("cooldown contacted Notion")
      assert_no_enqueued_jobs do
        post github_activity_update_path
        post leetcode_activity_update_path
        post notion_activity_update_path
        post activity_update_path
      end
      assert_equal 4, leetcode.daily_activities.find_by!(activity_date: Date.current).submission_count
      assert_nil leetcode.reload.last_sync_error
      assert_nil notion.reload.last_sync_error
      assert_predicate github.reload, :sync_status_ready?
    end
  end

  test "a LeetCode failure retains saved activity and does not block Notion or GitHub" do
    github, leetcode, notion = connect_providers(@user)
    activity = leetcode.daily_activities.create!(activity_date: Date.current, submission_count: 7)
    cached = cache_application(notion)
    sign_in

    with_provider_responses do |calendar, _client|
      calendar.define_singleton_method(:call) { raise Leetcode::SubmissionCalendar::AccessBlocked, "private detail" }
      post activity_update_path
    end

    assert_redirected_to root_path
    assert_equal 7, activity.reload.submission_count
    assert_nil leetcode.reload.last_synced_at
    assert_not_nil leetcode.last_sync_error
    assert_not NotionApplication.exists?(cached.id)
    assert_not_nil notion.reload.last_synced_at
    assert_predicate github.reload, :sync_status_queued?
    assert Rails.cache.exist?("leetcode-activity-update:global-suspension")
    assert_includes flash[:alert], "LeetCode"
    assert_not_includes flash[:alert], "private detail"
    assert_includes flash[:notice], "Notion"
  end

  test "GitHub reauthorization and Notion failure do not prevent a Practice update" do
    github, leetcode, notion = connect_providers(@user)
    github.update!(sync_status: "reauthorization_required")
    cached = cache_application(notion)
    sign_in

    with_provider_responses do |_calendar, client|
      client.error = Notion::ApiClient::Error.new("private detail")
      assert_no_enqueued_jobs { post activity_update_path }
    end

    assert_redirected_to root_path
    assert_equal 4, leetcode.daily_activities.find_by!(activity_date: Date.current).submission_count
    assert NotionApplication.exists?(cached.id)
    assert_nil notion.reload.last_synced_at
    assert_not_nil notion.last_sync_error
    assert_predicate github.reload, :sync_status_reauthorization_required?
    assert_includes flash[:alert], "GitHub"
    assert_includes flash[:alert], "Notion"
    assert_not_includes flash[:alert], "private detail"
    assert_includes flash[:notice], "LeetCode"
  end

  test "handles no connections and updates a sole connected service" do
    sign_in
    assert_no_enqueued_jobs { post activity_update_path }
    assert_redirected_to root_path
    assert_not_nil flash[:alert]

    leetcode = @user.create_leetcode_connection!(
      username: "BulkUser", tracking_started_on: Date.current, verified_at: Time.current
    )
    with_provider_responses { post activity_update_path }
    assert_equal 4, leetcode.daily_activities.find_by!(activity_date: Date.current).submission_count
  end

  private
    def sign_in
      post sign_in_path, params: { session: { email_address: "bulk@example.com", password: PASSWORD } }
      assert_redirected_to root_path
    end

    def connect_providers(user)
      identity = user.external_identities.create!(
        provider: "github", provider_uid: "github-#{user.id}", provider_username: "BulkUser"
      )
      github = identity.create_github_connection!(
        tracking_started_on: Date.current, access_token: "access-token", refresh_token: "refresh-token",
        access_token_expires_at: 1.hour.from_now
      )
      leetcode = user.create_leetcode_connection!(
        username: "BulkUser#{user.id}", tracking_started_on: Date.current, verified_at: Time.current
      )
      notion = user.create_notion_connection!(
        workspace_id: "workspace-#{user.id}", workspace_name: "Example workspace",
        bot_id: "bot-#{user.id}", owner_user_id: "owner-#{user.id}",
        access_token: "access-token", refresh_token: "refresh-token",
        tracking_started_on: Date.current, authorized_at: Time.current
      )
      [ github, leetcode, notion ]
    end

    def cache_application(connection)
      connection.applications.create!(
        provider_page_id: "cached", applied_on: Date.current,
        company_name: "Example Company", role: "Developer", current_status: "Applied",
        provider_last_edited_at: Time.current
      )
    end

    def with_provider_responses
      original_calendar = Leetcode::SubmissionCalendar.method(:new)
      original_notion = Notion::ApiClient.method(:new)
      calendar = Object.new
      calendar.define_singleton_method(:call) do
        Leetcode::SubmissionCalendar::Result.new(
          username: @username,
          days: [ Leetcode::SubmissionCalendar::Day.new(activity_date: Date.current, submission_count: 4) ]
        )
      end
      Leetcode::SubmissionCalendar.define_singleton_method(:new) do |username:, year:|
        calendar.instance_variable_set(:@username, username)
        calendar
      end
      client = NotionClient.new
      Notion::ApiClient.define_singleton_method(:new) { |**| client }
      yield calendar, client
    ensure
      Leetcode::SubmissionCalendar.define_singleton_method(:new, original_calendar)
      Notion::ApiClient.define_singleton_method(:new, original_notion)
    end
end
