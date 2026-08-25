require "test_helper"

class LeetcodeActivityUpdatesControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    Rails.cache.clear
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "requires authentication without constructing the synchronization service" do
    with_sync_factory(->(**) { flunk "synchronization service was constructed" }) do
      post leetcode_activity_update_path
    end

    assert_response :see_other
    assert_redirected_to sign_in_path
    assert_equal "Please sign in to continue.", flash[:alert]
  end

  test "handles a missing connection without constructing the synchronization service" do
    user = create_verified_user(email_address: "developer@example.com")
    sign_in_as(user)

    with_sync_factory(->(**) { flunk "synchronization service was constructed" }) do
      post leetcode_activity_update_path
    end

    assert_response :see_other
    assert_redirected_to root_path
    assert_equal "Connect LeetCode before updating activity.", flash[:alert]
  end

  test "calls synchronization exactly once inline for only the current user's connection" do
    current_user = create_verified_user(email_address: "current@example.com")
    current_connection = create_connection(current_user, username: "CurrentUser")
    other_user = create_verified_user(email_address: "other@example.com")
    other_connection = create_connection(other_user, username: "OtherUser")
    sign_in_as(current_user)
    calls = []

    with_sync_factory(sync_factory(calls:)) do
      post leetcode_activity_update_path,
        params: { user_id: other_user.id, leetcode_connection_id: other_connection.id }
    end

    assert_response :see_other
    assert_redirected_to root_path
    assert_equal [ current_connection ], calls
    assert_equal "LeetCode activity update completed.", flash[:notice]
    assert_nil flash[:alert]
  end

  test "a repeated connection update remains cached and makes no second call" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user, username: "ExampleUser")
    sign_in_as(user)
    calls = []

    with_sync_factory(sync_factory(calls:)) do
      post leetcode_activity_update_path
      assert_response :see_other

      travel 14.minutes + 59.seconds do
        post leetcode_activity_update_path
      end
    end

    assert_equal [ connection ], calls
    assert_equal "LeetCode activity was recently updated. Please wait before updating again.", flash[:notice]
  end

  test "a global overlap makes no call and releases that connection's cooldown claim" do
    first_user = create_verified_user(email_address: "first@example.com")
    first_connection = create_connection(first_user, username: "FirstUser")
    second_user = create_verified_user(email_address: "second@example.com")
    second_connection = create_connection(second_user, username: "SecondUser")
    calls = []

    travel_to Time.utc(2026, 8, 25, 12) do
      sign_in_as(first_user)
      with_sync_factory(sync_factory(calls:)) do
        post leetcode_activity_update_path
        sign_out
        sign_in_as(second_user)

        post leetcode_activity_update_path
        assert_equal "Another LeetCode activity update is in progress. Try again shortly.", flash[:notice]

        travel 5.seconds
        post leetcode_activity_update_path
      end
    end

    assert_equal [ first_connection, second_connection ], calls
  end

  test "access blocking opens a global suspension that prevents a later service call" do
    first_user = create_verified_user(email_address: "first@example.com")
    first_connection = create_connection(first_user, username: "FirstUser")
    second_user = create_verified_user(email_address: "second@example.com")
    create_connection(second_user, username: "SecondUser")
    sign_in_as(first_user)
    calls = []
    access_blocked = Leetcode::SyncActivities::AccessBlocked.new("provider detail that must stay private")

    with_sync_factory(sync_factory(calls:, error: access_blocked)) do
      post leetcode_activity_update_path
      assert_response :see_other
      assert_match(/LeetCode temporarily blocked activity updates/, flash[:alert])
      assert_not_includes flash[:alert], "provider detail"

      sign_out
      sign_in_as(second_user)
      travel 6.seconds
      post leetcode_activity_update_path
    end

    assert_equal [ first_connection ], calls
    assert_equal "LeetCode activity updates are temporarily paused. Try again later.", flash[:alert]
  end

  test "an ordinary provider failure is scoped and preserves cached activity" do
    first_user = create_verified_user(email_address: "first@example.com")
    first_connection = create_connection(first_user, username: "FirstUser")
    activity = first_connection.daily_activities.create!(
      activity_date: first_connection.tracking_started_on,
      submission_count: 7
    )
    second_user = create_verified_user(email_address: "second@example.com")
    second_connection = create_connection(second_user, username: "SecondUser")
    sign_in_as(first_user)
    calls = []
    error = Leetcode::SyncActivities::Error.new("upstream secret")

    with_sync_factory(sync_factory(calls:, error:, error_for: first_connection)) do
      post leetcode_activity_update_path
      assert_response :see_other
      assert_redirected_to root_path
      assert_equal "LeetCode activity could not be updated. Your saved activity is still available.", flash[:alert]
      assert_not_includes flash[:alert], "upstream secret"

      sign_out
      sign_in_as(second_user)
      travel 6.seconds
      post leetcode_activity_update_path
    end

    assert_equal [ first_connection, second_connection ], calls
    assert_equal "LeetCode activity update completed.", flash[:notice]
    assert_equal 7, activity.reload.submission_count
    assert_equal 1, first_connection.daily_activities.count
  end

  test "requires a CSRF token when forgery protection is enabled" do
    user = create_verified_user(email_address: "developer@example.com")
    create_connection(user, username: "ExampleUser")
    sign_in_as(user)
    previous_setting = LeetcodeActivityUpdatesController.allow_forgery_protection
    LeetcodeActivityUpdatesController.allow_forgery_protection = true

    with_sync_factory(->(**) { flunk "synchronization service was constructed" }) do
      post leetcode_activity_update_path
    end

    assert_response :unprocessable_entity
  ensure
    LeetcodeActivityUpdatesController.allow_forgery_protection = previous_setting
  end

  private
    def with_sync_factory(factory)
      original_factory = Leetcode::SyncActivities.method(:new)
      Leetcode::SyncActivities.define_singleton_method(:new, factory)
      yield
    ensure
      Leetcode::SyncActivities.define_singleton_method(:new, original_factory)
    end

    def sync_factory(calls:, error: nil, error_for: nil)
      lambda do |connection:|
        Object.new.tap do |service|
          service.define_singleton_method(:call) do
            calls << connection
            raise error if error && (!error_for || error_for == connection)

            :synchronized
          end
        end
      end
    end

    def create_verified_user(email_address:)
      User.create!.tap do |user|
        user.create_password_credential!(
          email_address:,
          password: PASSWORD,
          password_confirmation: PASSWORD,
          email_verified_at: Time.current
        )
      end
    end

    def create_connection(user, username:)
      user.create_leetcode_connection!(
        username:,
        tracking_started_on: Date.current,
        verified_at: Time.current
      )
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
      assert_redirected_to root_path
    end

    def sign_out
      delete sign_out_path
      assert_response :see_other
    end
end
