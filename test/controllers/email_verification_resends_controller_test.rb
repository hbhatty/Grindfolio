require "test_helper"

class EmailVerificationResendsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PASSWORD = "correct horse battery staple"
  REMOTE_IP = "203.0.113.42"
  NOW = Time.zone.local(2026, 8, 21, 12)

  setup do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  teardown do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  test "GET renders an accessible email form without a populated address" do
    get new_email_verification_resend_url

    assert_response :success
    assert_select "h1", "Resend verification email"
    assert_select "form[action='#{email_verification_resend_path}'][method='post']"
    assert_select "label[for='email_verification_resend_email_address']", "Email address"
    assert_select "input[type='email'][name='email_verification_resend[email_address]'][autocomplete='email'][required][maxlength='254']"
    assert_select "input[name='email_verification_resend[email_address]'][value]", count: 0
  end

  test "signup success page links to the resend form" do
    get sign_up_success_url

    assert_response :success
    assert_select "a[href='#{new_email_verification_resend_path}']", /Request another verification email/
  end

  test "normalizes a pending address and queues exactly one verification email" do
    credential = create_credential(email_address: "developer@example.com")
    original_updated_at = credential.updated_at

    assert_no_difference -> { Session.count } do
      assert_enqueued_email_with EmailVerificationMailer, :verify, args: [ credential ] do
        post_resend("  DEVELOPER@Example.COM ")
      end
    end

    assert_neutral_acceptance
    assert_nil credential.reload.email_verified_at
    assert_equal original_updated_at, credential.updated_at
  end

  test "unknown, verified, and cooling-down addresses receive the same neutral response without email" do
    pending = create_credential(email_address: "pending@example.com")
    create_credential(email_address: "verified@example.com", verified: true)

    assert_no_enqueued_emails do
      post_resend("unknown@example.com")
    end
    unknown_response = neutral_response

    assert_no_enqueued_emails do
      post_resend("verified@example.com")
    end
    verified_response = neutral_response

    assert_enqueued_emails 1 do
      post_resend(pending.email_address)
    end

    assert_no_enqueued_emails do
      post_resend(pending.email_address)
    end
    cooldown_response = neutral_response

    assert_equal unknown_response, verified_response
    assert_equal unknown_response, cooldown_response
    assert_neutral_acceptance
  end

  test "allows another email at the exact one-minute cooldown boundary" do
    credential = create_credential(email_address: "boundary@example.com")

    travel_to NOW do
      assert_enqueued_emails 1 do
        post_resend(credential.email_address)
      end

      travel 59.seconds
      assert_no_enqueued_emails do
        post_resend(credential.email_address)
      end

      travel 1.second
      assert_enqueued_emails 1 do
        post_resend(credential.email_address)
      end
    end
  end

  test "rate limits the eleventh request from one IP within three minutes" do
    EmailVerificationResendsController::RESEND_RATE_LIMIT.times do |attempt|
      post_resend("unknown-#{attempt}@example.com")
      assert_neutral_acceptance
    end

    assert_no_enqueued_emails do
      post_resend("unknown-final@example.com")
    end

    assert_response :too_many_requests
    assert_select "h1", "Please try again later"
  end

  test "does not queue email without a valid CSRF token" do
    credential = create_credential(email_address: "csrf@example.com")
    previous_setting = EmailVerificationResendsController.allow_forgery_protection
    EmailVerificationResendsController.allow_forgery_protection = true

    assert_no_enqueued_emails do
      post_resend(credential.email_address)
    end

    assert_response :unprocessable_entity
  ensure
    EmailVerificationResendsController.allow_forgery_protection = previous_setting
  end

  private
    def post_resend(email_address)
      post email_verification_resend_path,
        params: { email_verification_resend: { email_address: } },
        headers: { "REMOTE_ADDR" => REMOTE_IP }
    end

    def assert_neutral_acceptance
      assert_response :see_other
      assert_redirected_to email_verification_resend_accepted_url
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
