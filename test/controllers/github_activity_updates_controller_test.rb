require "test_helper"

class GithubActivityUpdatesControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"
  TURBO_STREAM_HEADERS = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    Current.reset
    Rails.cache.clear
    clear_enqueued_jobs
  end

  teardown do
    Current.reset
    Rails.cache.clear
    clear_enqueued_jobs
  end

  test "requires authentication without enqueueing an update" do
    assert_no_enqueued_jobs do
      post github_activity_update_path
    end

    assert_response :see_other
    assert_redirected_to sign_in_path
    assert_equal "Please sign in to continue.", flash[:alert]
  end

  test "handles a missing GitHub connection without enqueueing" do
    user = create_verified_user(email_address: "developer@example.com")
    sign_in_as(user)

    assert_no_enqueued_jobs do
      post github_activity_update_path
    end

    assert_response :see_other
    assert_redirected_to root_path
    assert_equal "Connect GitHub before updating activity.", flash[:alert]
  end

  test "accepts an in-place update for only the current user's connection" do
    current_user = create_verified_user(email_address: "current@example.com")
    current_connection = create_connection(current_user, provider_uid: "current-github")
    other_user = create_verified_user(email_address: "other@example.com")
    other_connection = create_connection(other_user, provider_uid: "other-github")
    sign_in_as(current_user)

    assert_enqueued_with job: Github::SyncContributionsJob, args: [ current_connection.id ] do
      post github_activity_update_path,
        params: { user_id: other_user.id, github_connection_id: other_connection.id },
        headers: TURBO_STREAM_HEADERS
    end

    assert_response :accepted
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace'][target='github_provider']"
    assert_select "turbo-stream[action='replace'][target='github_activity']"
    assert_includes response.body, "Updating GitHub activity…"
    assert_includes response.body, "aria-live=\"polite\""
    assert_includes response.body, "disabled"
    assert_nil flash[:notice]
    assert_predicate current_connection.reload, :sync_status_queued?
    assert_predicate other_connection.reload, :sync_status_pending?
  end

  test "keeps a safe no-JavaScript fallback without a queued flash" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user, provider_uid: "42")
    sign_in_as(user)

    assert_enqueued_with job: Github::SyncContributionsJob, args: [ connection.id ] do
      post github_activity_update_path
    end

    assert_response :see_other
    assert_redirected_to root_path
    assert_nil flash[:notice]
    assert_predicate connection.reload, :sync_status_queued?
    follow_redirect!
    assert_response :success
    assert_select ".heatmap-sync-status", /Updating GitHub activity/
  end

  test "refreshes only the focused status without enqueueing" do
    travel_to Time.utc(2026, 8, 23, 12) do
      user = create_verified_user(email_address: "developer@example.com")
      connection = create_connection(
        user,
        provider_uid: "42",
        sync_status: "ready",
        last_synced_at: Time.current
      )
      connection.daily_contributions.create!(
        activity_date: Date.current,
        contribution_count: 4,
        contribution_level: "FOURTH_QUARTILE"
      )
      other_user = create_verified_user(email_address: "other@example.com")
      other_connection = create_connection(
        other_user,
        provider_uid: "other-github",
        sync_status: "ready",
        last_synced_at: Time.current
      )
      other_connection.daily_contributions.create!(
        activity_date: Date.current,
        contribution_count: 99,
        contribution_level: "FOURTH_QUARTILE"
      )
      sign_in_as(user)

      assert_no_enqueued_jobs do
        get github_activity_update_path,
          params: { github_connection_id: other_connection.id },
          headers: TURBO_STREAM_HEADERS
      end

      assert_response :success
      assert_select "turbo-stream[action='replace'][target='github_provider']"
      assert_select "turbo-stream[action='replace'][target='github_activity']"
      assert_includes response.body, "Updated just now"
      assert_includes response.body, "August 23, 2026: 4 contributions"
      assert_not_includes response.body, "Activity providers"
      assert_not_includes response.body, "99 contributions"
    end
  end

  test "shows temporary failure and reauthorization as different actions" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user, provider_uid: "42", sync_status: "error")
    sign_in_as(user)

    get github_activity_update_path, headers: TURBO_STREAM_HEADERS

    assert_response :success
    assert_includes response.body, "existing activity is still available"
    assert_includes response.body, "Retry update"
    assert_not_includes response.body, "Reauthorize GitHub"

    connection.update!(
      sync_status: "reauthorization_required",
      last_sync_error: Github::SyncContributions::REAUTHORIZATION_REQUIRED_MESSAGE
    )

    assert_no_enqueued_jobs do
      get github_activity_update_path, headers: TURBO_STREAM_HEADERS
    end

    assert_includes response.body, "Reconnect GitHub to continue updating activity."
    assert_includes response.body, "Reauthorize GitHub"
    assert_not_includes response.body, "Retry update"
    assert_includes response.body, "data-turbo=\"false\""
  end

  test "suppresses updates during the atomic five-minute cooldown" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user, provider_uid: "42")
    sign_in_as(user)

    travel_to Time.utc(2026, 8, 23, 12) do
      assert_enqueued_with job: Github::SyncContributionsJob, args: [ connection.id ] do
        post github_activity_update_path
      end
      clear_enqueued_jobs
      connection.update!(sync_status: "ready", last_synced_at: Time.current)

      travel 4.minutes + 59.seconds
      assert_no_enqueued_jobs do
        post github_activity_update_path, headers: TURBO_STREAM_HEADERS
      end
      assert_response :success
      assert_includes response.body, "Please wait a few minutes before trying again."
      assert_predicate connection.reload, :sync_status_ready?

      travel 1.second
      assert_enqueued_with job: Github::SyncContributionsJob, args: [ connection.id ] do
        post github_activity_update_path, headers: TURBO_STREAM_HEADERS
      end
      assert_response :accepted
      assert_predicate connection.reload, :sync_status_queued?
    end
  end

  test "does not enqueue a queued or syncing connection twice" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user, provider_uid: "42", sync_status: "queued")
    sign_in_as(user)

    %w[queued syncing].each do |status|
      connection.update!(sync_status: status)

      assert_no_enqueued_jobs do
        post github_activity_update_path, headers: TURBO_STREAM_HEADERS
      end

      assert_response :success
      assert_includes response.body, "already updating"
      assert_includes response.body, "Updating…"
    end
  end

  test "does not enqueue while GitHub needs reauthorization" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user, provider_uid: "42", sync_status: "reauthorization_required")
    sign_in_as(user)

    assert_no_enqueued_jobs do
      post github_activity_update_path, headers: TURBO_STREAM_HEADERS
    end

    assert_response :success
    assert_predicate connection.reload, :sync_status_reauthorization_required?
    assert_includes response.body, "Reauthorize GitHub"
  end

  test "releases the cooldown and exposes a retry when enqueueing fails" do
    user = create_verified_user(email_address: "developer@example.com")
    connection = create_connection(user, provider_uid: "42")
    sign_in_as(user)

    previous_adapter = Github::SyncContributionsJob.queue_adapter
    failing_adapter = Object.new
    failing_adapter.define_singleton_method(:enqueue) do |_job|
      raise ActiveJob::EnqueueError, "queue offline"
    end
    failing_adapter.define_singleton_method(:enqueue_at) do |_job, _timestamp|
      raise ActiveJob::EnqueueError, "queue offline"
    end
    Github::SyncContributionsJob.queue_adapter = failing_adapter

    begin
      assert_no_enqueued_jobs do
        post github_activity_update_path, headers: TURBO_STREAM_HEADERS
      end
    ensure
      Github::SyncContributionsJob.queue_adapter = previous_adapter
    end

    assert_response :success
    assert_predicate connection.reload, :sync_status_error?
    assert_equal GithubActivityUpdatesController::ENQUEUE_FAILURE_MESSAGE, connection.last_sync_error
    assert_includes response.body, "GitHub activity could not start. Try again."
    assert_includes response.body, "Retry update"
    assert_not_includes response.body, "queue"

    assert_enqueued_with job: Github::SyncContributionsJob, args: [ connection.id ] do
      post github_activity_update_path, headers: TURBO_STREAM_HEADERS
    end
    assert_response :accepted
  end

  test "requires a CSRF token when forgery protection is enabled" do
    user = create_verified_user(email_address: "developer@example.com")
    create_connection(user, provider_uid: "42")
    sign_in_as(user)
    previous_setting = GithubActivityUpdatesController.allow_forgery_protection
    GithubActivityUpdatesController.allow_forgery_protection = true

    assert_no_enqueued_jobs do
      post github_activity_update_path
    end

    assert_response :unprocessable_entity
  ensure
    GithubActivityUpdatesController.allow_forgery_protection = previous_setting
  end

  private
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

    def create_connection(
      user,
      provider_uid:,
      sync_status: "pending",
      last_synced_at: nil
    )
      identity = user.external_identities.create!(
        provider: "github",
        provider_uid:,
        provider_username: "octocat"
      )
      identity.create_github_connection!(
        tracking_started_on: Date.current,
        access_token: "access-token",
        refresh_token: "refresh-token",
        access_token_expires_at: 1.hour.from_now,
        sync_status:,
        last_synced_at:
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
end
