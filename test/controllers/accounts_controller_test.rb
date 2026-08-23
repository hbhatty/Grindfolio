require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    Rails.cache.clear
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "requires authentication to view the account" do
    get account_path

    assert_response :see_other
    assert_redirected_to sign_in_path
    assert_equal "Please sign in to continue.", flash[:alert]
    assert_not_includes response.body, "developer@example.com"
  end

  test "requires authentication before updating an account" do
    user = create_verified_user(email_address: "developer@example.com")

    assert_no_changes -> { user.reload.time_zone } do
      patch account_path, params: { user: { time_zone: "America/Toronto" } }
    end

    assert_response :see_other
    assert_redirected_to sign_in_path
  end

  test "shows only the current account with an accessible time zone form" do
    current_user = create_verified_user(
      email_address: "current@example.com",
      time_zone: "America/Toronto"
    )
    create_verified_user(email_address: "other@example.com")
    sign_in_as(current_user)

    get account_path

    assert_response :success
    assert_select "h1", "Your Gridfolio account"
    assert_select "dd", "current@example.com"
    assert_select "body", text: /other@example\.com/, count: 0
    assert_select "form[action='#{account_path}'][method='post']" do
      assert_select "input[name='_method'][value='patch']"
      assert_select "label[for='user_time_zone']", "Time zone"
      assert_select "select[name='user[time_zone]'][required][aria-describedby='time-zone-help']" do
        assert_select "option[value='America/Toronto'][selected]"
      end
      assert_select "input[type='submit'][value='Save time zone']"
    end
    assert_select "p", text: /account and activity are private/i
  end

  test "shows a GitHub connection action and two clearly unavailable provider connections" do
    sign_in_as(create_verified_user(email_address: "developer@example.com"))

    get account_path

    assert_response :success
    assert_select "section[aria-labelledby='provider-connections-heading']" do
      assert_select "form[action='/auth/github'][method='post'][data-turbo='false']" do
        assert_select "button[type='submit']", "Connect GitHub"
      end
      assert_select "button[type='button'][disabled]", count: 2
      assert_select "button[disabled]", "Connect LeetCode — Coming soon"
      assert_select "button[disabled]", "Connect Notion — Coming soon"
      assert_select "a[href*='leetcode']", count: 0
      assert_select "a[href*='notion']", count: 0
    end
  end

  test "shows the current GitHub account, pending status, and reauthorization action" do
    user = create_verified_user(email_address: "developer@example.com")
    identity = user.external_identities.create!(
      provider: "github",
      provider_uid: "42",
      provider_username: "octocat"
    )
    identity.create_github_connection!(
      tracking_started_on: Date.new(2026, 8, 22),
      access_token: "access-token",
      refresh_token: "refresh-token",
      access_token_expires_at: Time.utc(2026, 8, 22, 20)
    )
    sign_in_as(user)

    get account_path

    assert_response :success
    assert_select "dt", "Connected account"
    assert_select "dd", "octocat"
    assert_select ".account-provider-status--pending", "Not updated"
    assert_select "dt", "Tracking started"
    assert_select "dd", "August 22, 2026"
    assert_select "form[action='/auth/github'][method='post'][data-turbo='false']" do
      assert_select "button[type='submit']", "Reauthorize GitHub"
    end
    assert_not_includes response.body, "access-token"
    assert_not_includes response.body, "refresh-token"
  end

  test "updates only the current user's time zone" do
    current_user = create_verified_user(email_address: "current@example.com")
    other_user = create_verified_user(email_address: "other@example.com")
    created_at = current_user.created_at
    sign_in_as(current_user)

    patch account_path,
      params: {
        user: {
          id: other_user.id,
          time_zone: "America/Toronto",
          created_at: 10.years.ago
        }
      }

    assert_response :see_other
    assert_redirected_to account_path
    assert_equal "Your time zone has been saved.", flash[:notice]
    assert_equal "America/Toronto", current_user.reload.time_zone
    assert_equal created_at, current_user.created_at
    assert_nil other_user.reload.time_zone
  end

  test "rejects blank and invalid submitted time zones" do
    user = create_verified_user(
      email_address: "developer@example.com",
      time_zone: "America/Toronto"
    )
    sign_in_as(user)

    [ "", "Not/A_Time_Zone" ].each do |time_zone|
      patch account_path, params: { user: { time_zone: } }

      assert_response :unprocessable_entity
      assert_select "[role='alert']", text: /Time zone is not a valid IANA time zone/
      assert_equal "America/Toronto", user.reload.time_zone
    end
  end

  test "updating the account requires a CSRF token when forgery protection is enabled" do
    user = create_verified_user(email_address: "developer@example.com")
    sign_in_as(user)
    previous_setting = AccountsController.allow_forgery_protection
    AccountsController.allow_forgery_protection = true

    assert_no_changes -> { user.reload.time_zone } do
      patch account_path, params: { user: { time_zone: "America/Toronto" } }
    end

    assert_response :unprocessable_entity
  ensure
    AccountsController.allow_forgery_protection = previous_setting
  end

  private
    def create_verified_user(email_address:, time_zone: nil)
      user = User.create!(time_zone:)
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
      assert_redirected_to root_path
    end
end
