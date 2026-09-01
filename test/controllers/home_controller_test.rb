require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    clear_enqueued_jobs
  end

  teardown do
    Current.reset
    clear_enqueued_jobs
  end

  test "renders the Grindfolio home page" do
    get root_url

    assert_response :success
    assert_select "h1.marketing-wordmark", "Grindfolio"
    assert_select ".marketing-lede", "Track building, practice, and job applications on one private daily timeline."
    assert_select "a[href='#{sign_up_path}']", "Create an account"
    assert_select "a[href='#{sign_in_path}']", "Sign in"
    assert_select "a[href='#{account_path}']", count: 0
    assert_select "form[action='#{sign_out_path}']", count: 0
    assert_select "p", text: "You are signed in.", count: 0
    assert_nil Current.session
  end

  test "renders the signed-in state for an active restored session" do
    user = User.create!
    credential = user.create_password_credential!(
      email_address: "developer@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
    token = credential.generate_token_for(:email_verification)

    post confirm_email_verification_url(token:)

    assert_redirected_to root_url
    assert_predicate user.sessions.sole, :active?

    get root_url

    assert_response :success
    assert_select "h1", "Activity"
    assert_select "section[aria-label='Activity providers'] article", count: 3
    assert_select "h2", "GitHub"
    assert_select "h2", "LeetCode"
    assert_select "h2", "Notion"
    assert_select "section[aria-labelledby='build-heatmap-heading']" do
      assert_select "[data-heatmap-target='date']", "Today"
    end
    assert_select "a[href='#{account_path}']", "Account"
    assert_select "a[href='#{sign_up_path}']", count: 0
    assert_select "a[href='#{sign_in_path}']", count: 0
    assert_select "form[action='#{sign_out_path}'][method='post']" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button", "Sign out"
    end
    assert_nil Current.session
  end

  test "renders every heatmap from January through today" do
    travel_to Time.utc(2026, 8, 29, 12) do
      create_signed_in_user

      get root_url

      assert_response :success
      assert_select "section[aria-labelledby='build-heatmap-heading']" do
        assert_select ".heatmap-calendar[style='--heatmap-weeks: 53;']"
        assert_select "[role='grid'][aria-label='GitHub activity for 2026']" do
          assert_select ".heatmap-cell", count: 241 do |cells|
            assert_equal "January 01, 2026: not tracked", cells.first["aria-label"]
            assert_includes cells.first["style"], "grid-column: 2;"
            assert_equal "January 04, 2026: not tracked", cells[3]["aria-label"]
            assert_includes cells[3]["style"], "grid-column: 3;"
            assert_equal "August 29, 2026: not tracked", cells.last["aria-label"]
          end
        end
      end
      assert_select "section[aria-labelledby='practice-heatmap-heading']" do
        assert_select "[role='grid'][aria-label='LeetCode Practice activity for 2026, using LeetCode dates in UTC']" do
          assert_select ".heatmap-cell", count: 241 do |cells|
            assert_equal "January 01, 2026 — LeetCode date (UTC): not tracked", cells.first["aria-label"]
            assert_equal "August 29, 2026 — LeetCode date (UTC): not tracked", cells.last["aria-label"]
          end
        end
      end
      assert_select "section[aria-labelledby='apply-heatmap-heading']" do
        assert_select "[role='grid'][aria-label='Notion Apply activity for 2026, using mapped Application Dates']" do
          assert_select ".heatmap-cell", count: 241 do |cells|
            assert_equal "January 01, 2026: not tracked", cells.first["aria-label"]
            assert_equal "August 29, 2026: not tracked", cells.last["aria-label"]
          end
        end
      end
    end
  end

  test "renders saved GitHub contributions without importing earlier dates" do
    travel_to Time.utc(2026, 8, 23, 12) do
      user = create_signed_in_user
      identity = user.external_identities.create!(
        provider: "github",
        provider_uid: "42",
        provider_username: "octocat"
      )
      connection = identity.create_github_connection!(
        tracking_started_on: Date.new(2026, 8, 21),
        access_token: "access-token",
        refresh_token: "refresh-token",
        access_token_expires_at: 1.hour.from_now,
        sync_status: "ready",
        last_synced_at: Time.utc(2026, 8, 23, 11, 30)
      )
      connection.daily_contributions.create!(
        activity_date: Date.new(2026, 8, 23),
        contribution_count: 1,
        contribution_level: "FOURTH_QUARTILE"
      )

      get root_url

      assert_response :success
      assert_select ".provider-card--green", text: /Connected as @octocat/
      assert_select ".heatmap-sync", text: /Updated.*UTC/
      assert_select "button[aria-label='August 20, 2026: not tracked'].heatmap-cell--untracked"
      assert_select "button[aria-label='August 22, 2026: not synced yet'].heatmap-cell--pending"
      assert_select "button[aria-label='August 23, 2026: 1 contribution'].heatmap-cell--fourth" do
        assert_select "[data-count='1'][data-unit='contribution'][data-state='tracked'][aria-pressed='true']"
      end
    end
  end

  test "shows the last synchronization time in the user's selected time zone" do
    travel_to Time.utc(2026, 8, 23, 12) do
      user = create_signed_in_user(time_zone: "America/Toronto")
      identity = user.external_identities.create!(
        provider: "github",
        provider_uid: "42",
        provider_username: "octocat"
      )
      identity.create_github_connection!(
        tracking_started_on: Date.new(2026, 8, 23),
        access_token: "access-token",
        refresh_token: "refresh-token",
        access_token_expires_at: 1.hour.from_now,
        sync_status: "ready",
        last_synced_at: Time.utc(2026, 8, 23, 11, 30)
      )

      get root_url

      assert_select ".heatmap-sync", text: /23 Aug 07:30.*EDT/
    end
  end

  test "shows the pending GitHub state and update action without enqueueing on render" do
    user = create_signed_in_user
    create_github_connection(user, sync_status: "pending")

    assert_no_enqueued_jobs do
      get root_url
    end

    assert_response :success
    assert_select ".provider-status--pending", "Not updated"
    assert_select ".heatmap-sync-status", "Ready for first update"
    assert_select "form[action='#{github_activity_update_path}'][method='post']" do
      assert_select "button", "Update activity"
    end
  end

  test "shows the ready GitHub state and update action" do
    user = create_signed_in_user
    create_github_connection(
      user,
      sync_status: "ready",
      last_synced_at: Time.utc(2026, 8, 23, 11, 30)
    )

    get root_url

    assert_response :success
    assert_select ".provider-status--ready", "Updated"
    assert_select ".heatmap-sync-status", text: /Updated/
    assert_select "form[action='#{github_activity_update_path}'] button", "Update activity"
    assert_select "turbo-frame#github_activity[data-sync-active='false']"
  end

  test "shows the failed GitHub state with a retry action" do
    user = create_signed_in_user
    create_github_connection(
      user,
      sync_status: "error",
      last_sync_error: Github::SyncContributions::STORED_ERROR_MESSAGE
    )

    get root_url

    assert_response :success
    assert_select ".provider-status--error", "Update failed"
    assert_select ".heatmap-sync-status", /existing activity is still available/
    assert_select "form[action='#{github_activity_update_path}'] button", "Retry update"
  end

  test "shows the syncing GitHub state with an accessible disabled control" do
    user = create_signed_in_user
    create_github_connection(user, sync_status: "syncing")

    get root_url

    assert_response :success
    assert_select ".provider-status--syncing", "Updating"
    assert_select ".heatmap-sync-status[role='status'][aria-live='polite']", /Updating GitHub activity/
    assert_select "button.heatmap-sync-action[disabled][aria-disabled='true']", "Updating…"
    assert_select "form[action='#{github_activity_update_path}']", count: 0
    assert_select "main[data-controller~='github-sync-refresh'][data-github-sync-refresh-url-value='#{github_activity_update_path}']"
    assert_select "turbo-frame#github_activity[data-sync-active='true']"
  end

  test "shows the durable queued state immediately" do
    user = create_signed_in_user
    create_github_connection(user, sync_status: "queued")

    get root_url

    assert_response :success
    assert_select ".provider-status--queued", "Updating"
    assert_select ".heatmap-sync-status", /Updating GitHub activity/
    assert_select ".heatmap-sync-progress[aria-hidden='true']"
    assert_select "turbo-frame#github_activity[data-sync-active='true']"
  end

  test "shows a bounded long-running update state" do
    user = create_signed_in_user
    connection = create_github_connection(user, sync_status: "syncing")
    connection.update_columns(updated_at: 2.minutes.ago)

    get root_url

    assert_response :success
    assert_select ".heatmap-sync-status", /taking longer than usual/
    assert_select "button.heatmap-sync-action[disabled]", "Updating…"
  end

  test "shows reauthorization as a distinct recovery action" do
    user = create_signed_in_user
    create_github_connection(
      user,
      sync_status: "reauthorization_required",
      last_sync_error: Github::SyncContributions::REAUTHORIZATION_REQUIRED_MESSAGE
    )

    get root_url

    assert_response :success
    assert_select ".provider-status--reauthorization_required", "Reconnect"
    assert_select ".heatmap-sync-status", "Reconnect GitHub to continue updating activity."
    assert_select "form[action='/auth/github'][data-turbo='false'] button", "Reauthorize GitHub"
    assert_select "form[action='#{github_activity_update_path}']", count: 0
  end

  test "renders cached LeetCode dashboard state without constructing a provider or sync client" do
    travel_to Time.utc(2026, 8, 25, 12) do
      user = create_signed_in_user
      connection = create_leetcode_connection(
        user,
        username: "CanonicalUser",
        tracking_started_on: Date.new(2026, 8, 23)
      )
      connection.update!(last_synced_at: Time.utc(2026, 8, 25, 11, 30))
      connection.daily_activities.create!(
        activity_date: Date.new(2026, 8, 24),
        submission_count: 0
      )
      connection.daily_activities.create!(
        activity_date: Date.new(2026, 8, 25),
        submission_count: 4
      )
      create_github_connection(user, sync_status: "ready", last_synced_at: Time.current)

      sync_factory = ->(**) { flunk "sync service was constructed by dashboard GET" }
      provider_factory = ->(**) { flunk "provider client was constructed by dashboard GET" }
      with_replaced_factory(Leetcode::SyncActivities, sync_factory) do
        with_replaced_factory(Leetcode::SubmissionCalendar, provider_factory) do
          get root_url
        end
      end

      assert_response :success
      assert_select ".provider-card--blue", text: /Connected as @CanonicalUser/
      assert_select ".provider-card--blue", text: /Unofficial beta/
      assert_select "section[aria-labelledby='practice-heatmap-heading']" do
        assert_select ".heatmap-caption", text: /LeetCode date \(UTC\).*not rebucketed/
        assert_select ".heatmap-sync-status", text: /Last updated.*UTC/
        assert_select "form[action='#{leetcode_activity_update_path}'] button[data-turbo-submits-with='Updating…']", "Update activity"
        assert_select "button[aria-label='August 22, 2026 — LeetCode date (UTC): not tracked'][data-state='untracked'][data-count='—']"
        assert_select "button[aria-label='August 23, 2026 — LeetCode date (UTC): not synchronized'][data-state='unsynchronized'][data-count='—']"
        assert_select "button[aria-label='August 24, 2026 — LeetCode date (UTC): raw submission count 0; synchronized with no submissions'][data-state='zero'][data-count='0']"
        assert_select "button[aria-label='August 25, 2026 — LeetCode date (UTC): raw submission count 4; active'][data-state='active'][data-count='4'][data-unit='submissions'][aria-pressed='true']"
        assert_select "[data-heatmap-target='date']", "August 25, 2026 — LeetCode date (UTC)"
        assert_select "[data-heatmap-target='message']", /raw submission count: 4.*LeetCode date \(UTC\)/
        assert_select "[data-heatmap-target='count']", "4"
        assert_select "[data-heatmap-target='unit']", "submissions"
      end
      assert_select "section[aria-labelledby='build-heatmap-heading'] h2", "GitHub activity"
      assert_select "form[action='#{github_activity_update_path}'] button", "Update activity"
    end
  end

  test "distinguishes never-updated and failed LeetCode dashboard states" do
    user = create_signed_in_user
    connection = create_leetcode_connection(
      user,
      username: "CanonicalUser",
      tracking_started_on: Date.current
    )

    get root_url

    assert_response :success
    assert_select "section[aria-labelledby='practice-heatmap-heading'] .heatmap-sync-status", "Never updated"

    connection.daily_activities.create!(
      activity_date: Date.current,
      submission_count: 3
    )

    connection.update!(last_sync_error: Leetcode::SyncActivities::STORED_ERROR_MESSAGE)
    get root_url

    assert_response :success
    assert_select "section[aria-labelledby='practice-heatmap-heading'] .heatmap-sync-status",
      "LeetCode activity could not be updated. Your saved activity is still available."
    assert_select "section[aria-labelledby='practice-heatmap-heading'] form[action='#{leetcode_activity_update_path}']"
    assert_select "section[aria-labelledby='practice-heatmap-heading'] button[data-state='active'][data-count='3'][aria-pressed='true']"
  end

  test "renders a disconnected Practice card without an update action" do
    create_signed_in_user

    get root_url

    assert_response :success
    assert_select ".provider-card--blue a[href='#{account_path}']", "Connect from Account"
    assert_select "section[aria-labelledby='practice-heatmap-heading']", text: /Connect LeetCode/
    assert_select "form[action='#{leetcode_activity_update_path}']", count: 0
  end

  test "renders cached Notion heatmap and day details without provider access" do
    travel_to Time.utc(2026, 8, 26, 20) do
      user = create_signed_in_user(time_zone: "America/Toronto")
      connection = create_notion_connection(user)
      connection.update!(
        last_synced_at: Time.current,
        last_synced_through_on: Date.new(2026, 8, 26)
      )
      connection.applications.create!(
        provider_page_id: "page-id",
        applied_on: Date.new(2026, 8, 26),
        company_name: "Example Company",
        role: "Software Engineering Intern",
        current_status: "Applied",
        provider_last_edited_at: Time.current
      )
      provider_factory = ->(**) { flunk "Notion provider client was constructed by dashboard GET" }

      with_replaced_factory(Notion::ApiClient, provider_factory) do
        get root_url
      end

      assert_response :success
      assert_select ".provider-card--orange", text: /Connected/
      assert_select "section[aria-labelledby='apply-heatmap-heading']" do
        assert_select "form[action='#{notion_activity_update_path}'] button[data-turbo-submits-with='Updating…']",
          "Update activity"
        assert_select "button[aria-label='August 26, 2026: 1 application'][data-state='active'][data-count='1'][data-unit='application'][aria-pressed='true']"
        assert_select "[data-heatmap-target='message']", /Example Company.*Software Engineering Intern.*Status: Applied/
        assert_select "[data-heatmap-target='count']", "1"
        assert_select "[data-heatmap-target='unit']", "application"
      end
    end
  end

  private
    def with_replaced_factory(factory_owner, replacement)
      original_factory = factory_owner.method(:new)
      factory_owner.define_singleton_method(:new, replacement)
      yield
    ensure
      factory_owner.define_singleton_method(:new, original_factory)
    end

    def create_signed_in_user(time_zone: nil)
      user = User.create!(time_zone:)
      credential = user.create_password_credential!(
        email_address: "connected-developer@example.com",
        password: PASSWORD,
        password_confirmation: PASSWORD
      )

      post confirm_email_verification_url(token: credential.generate_token_for(:email_verification))
      assert_redirected_to root_url
      user
    end

    def create_github_connection(
      user,
      sync_status:,
      last_synced_at: nil,
      last_sync_error: nil
    )
      identity = user.external_identities.create!(
        provider: "github",
        provider_uid: "42",
        provider_username: "octocat"
      )
      identity.create_github_connection!(
        tracking_started_on: Date.current,
        access_token: "access-token",
        refresh_token: "refresh-token",
        access_token_expires_at: 1.hour.from_now,
        sync_status:,
        last_synced_at:,
        last_sync_error:
      )
    end

    def create_leetcode_connection(user, username:, tracking_started_on:)
      user.create_leetcode_connection!(
        username:,
        tracking_started_on:,
        verified_at: Time.current
      )
    end

    def create_notion_connection(user)
      user.create_notion_connection!(
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
end
