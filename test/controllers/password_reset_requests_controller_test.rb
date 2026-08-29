require "test_helper"

class PasswordResetRequestsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PASSWORD = "correct horse battery staple"
  REMOTE_IP = "203.0.113.42"
  NOW = Time.zone.local(2026, 9, 1, 12)

  setup do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  teardown do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  test "GET renders an accessible reset request form linked from sign in" do
    get new_password_reset_request_url

    assert_response :success
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='password-reset-request-heading']"
    assert_select "h1#password-reset-request-heading", "Reset your password"
    assert_select "form[action='#{password_reset_request_path}'][method='post']"
    assert_select "label[for='password_reset_request_email_address']", "Email address"
    assert_select "input[type='email'][name='password_reset_request[email_address]'][autocomplete='email'][required][maxlength='254'][autofocus]" do |inputs|
      inputs.each do |input|
        assert_nil input["size"]
        assert_nil input["value"]
      end
    end

    get sign_in_url

    assert_response :success
    assert_select "a[href='#{new_password_reset_request_path}']", "Forgot your password?"
  end

  test "GET renders the neutral accepted response with a sign-in action" do
    get password_reset_request_accepted_url

    assert_response :success
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='password-reset-request-accepted-heading']"
    assert_select "h1#password-reset-request-accepted-heading", "Check your email"
    assert_select "p", /If a verified Grindfolio password account exists/
    assert_select "a[href='#{sign_in_path}']", "Continue to sign in"
  end

  test "normalizes a verified address and queues exactly one reset email without changing account state" do
    credential = create_credential(email_address: "developer@example.com", verified: true)
    original_updated_at = credential.updated_at

    assert_no_difference -> { Session.count } do
      assert_enqueued_email_with PasswordResetMailer, :reset, args: [ credential ] do
        post_reset_request("  DEVELOPER@Example.COM ")
      end
    end

    assert_neutral_acceptance
    assert_equal original_updated_at, credential.reload.updated_at
  end

  test "unknown, unverified, and cooling-down addresses share one response without email" do
    verified = create_credential(email_address: "verified@example.com", verified: true)
    create_credential(email_address: "pending@example.com")

    assert_no_enqueued_emails do
      post_reset_request("unknown@example.com")
    end
    unknown_response = neutral_response

    assert_no_enqueued_emails do
      post_reset_request("pending@example.com")
    end
    unverified_response = neutral_response

    assert_enqueued_emails 1 do
      post_reset_request(verified.email_address)
    end

    assert_no_enqueued_emails do
      post_reset_request(verified.email_address)
    end
    cooldown_response = neutral_response

    assert_equal unknown_response, unverified_response
    assert_equal unknown_response, cooldown_response
    assert_neutral_acceptance
  end

  test "allows another reset email at the one-minute cooldown boundary" do
    credential = create_credential(email_address: "boundary@example.com", verified: true)

    travel_to NOW do
      assert_enqueued_emails 1 do
        post_reset_request(credential.email_address)
      end

      travel 59.seconds
      assert_no_enqueued_emails do
        post_reset_request(credential.email_address)
      end

      travel 1.second
      assert_enqueued_emails 1 do
        post_reset_request(credential.email_address)
      end
    end
  end

  test "rate limits the eleventh request from one IP within three minutes" do
    PasswordResetRequestsController::REQUEST_RATE_LIMIT.times do |attempt|
      post_reset_request("unknown-#{attempt}@example.com")
      assert_neutral_acceptance
    end

    assert_no_enqueued_emails do
      post_reset_request("unknown-final@example.com")
    end

    assert_response :too_many_requests
    assert_select "section[aria-labelledby='password-reset-request-rate-limit-heading']"
    assert_select "h1#password-reset-request-rate-limit-heading", "Please try again later"
    assert_select "a[href='#{new_password_reset_request_path}']", "Try requesting another email"
  end

  test "does not queue email without a valid CSRF token" do
    credential = create_credential(email_address: "csrf@example.com", verified: true)
    previous_setting = PasswordResetRequestsController.allow_forgery_protection
    PasswordResetRequestsController.allow_forgery_protection = true

    assert_no_enqueued_emails do
      post_reset_request(credential.email_address)
    end

    assert_response :unprocessable_entity
  ensure
    PasswordResetRequestsController.allow_forgery_protection = previous_setting
  end

  private
    def post_reset_request(email_address)
      post password_reset_request_path,
        params: { password_reset_request: { email_address: } },
        headers: { "REMOTE_ADDR" => REMOTE_IP }
    end

    def assert_neutral_acceptance
      assert_response :see_other
      assert_redirected_to password_reset_request_accepted_url
    end

    def neutral_response
      [ response.status, response.location, response.body ]
    end

    def create_credential(email_address:, verified: false)
      PasswordCredential.create!(
        user: User.create!,
        email_address:,
        password: PASSWORD,
        password_confirmation: PASSWORD,
        email_verified_at: verified ? Time.current : nil
      )
    end
end
