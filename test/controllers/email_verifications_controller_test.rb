require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    @credential = PasswordCredential.create!(
      user: User.create!,
      email_address: "developer@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
    @token = @credential.generate_token_for(:email_verification)
  end

  test "GET shows confirmation without changing account state" do
    assert_no_changes -> { [ @credential.reload.email_verified_at, Session.count ] } do
      get email_verification_url(token: @token)
    end

    assert_response :success
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='email-verification-heading']"
    assert_select "h1#email-verification-heading", "Verify your email"
    assert_select "form[action='#{confirm_email_verification_path(token: @token)}'][method='post']"
    assert_select "input[type='submit'][value='Verify email']"
    assert_nil response.cookies[EmailVerificationsController::SESSION_COOKIE_NAME.to_s]
  end

  test "GET rejects an invalid token without creating a session" do
    assert_no_changes -> { [ @credential.reload.email_verified_at, Session.count ] } do
      get email_verification_url(token: "not-a-valid-token")
    end

    assert_response :unprocessable_entity
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='invalid-verification-heading']"
    assert_select "h1#invalid-verification-heading", "Verification link unavailable"
    assert_select "p", /invalid, expired, or has already been used/
    assert_select "a[href='#{new_email_verification_resend_path}']", "Request another verification email"
  end

  test "GET rejects an expired token" do
    travel_to(PasswordCredential::EMAIL_VERIFICATION_TOKEN_LIFETIME.from_now + 1.second) do
      get email_verification_url(token: @token)
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Verification link unavailable"
    assert_equal 0, Session.count
  end

  test "POST verifies the email, creates one session, and sets a browser cookie" do
    post confirm_email_verification_url(token: @token)

    assert_redirected_to root_url
    assert_not_nil @credential.reload.email_verified_at
    session = @credential.user.sessions.sole
    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
    cookie_value = set_cookie[/#{EmailVerificationsController::SESSION_COOKIE_NAME}=([^;]+)/, 1]

    assert_match(/--/, cookie_value)
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_not_includes set_cookie, "Secure"
    assert_equal session.expires_at.to_i, set_cookie.match(/expires=([^;]+)/i).then { |match| Time.httpdate(match[1]).to_i }

    follow_redirect!
    assert_select "#flash_stack.flash-stack", count: 1 do
      assert_select ".flash-message.flash-message--notice[role='status'][aria-atomic='true'][data-controller~='flash-message'][data-turbo-temporary]", count: 1 do
        assert_select ".flash-message__marker[aria-hidden='true']", count: 1
        assert_select ".flash-message__text", "Your email has been verified."
        assert_select "button.flash-message__dismiss[type='button'][data-action='flash-message#dismiss']", "Dismiss"
      end
    end
    assert_select ".flash-stack[role], .flash-stack[aria-live]", count: 0
  end

  test "POST is idempotent when the same token is replayed" do
    post confirm_email_verification_url(token: @token)
    assert_equal 1, Session.where(user: @credential.user).count

    post confirm_email_verification_url(token: @token)

    assert_response :unprocessable_entity
    assert_equal 1, Session.where(user: @credential.user).count
    assert_select "h1", "Verification link unavailable"
  end

  test "GET rejects a token after it has been used" do
    post confirm_email_verification_url(token: @token)

    get email_verification_url(token: @token)

    assert_response :unprocessable_entity
    assert_equal 1, Session.where(user: @credential.user).count
    assert_select "h1", "Verification link unavailable"
  end

  test "POST rejects an invalid token without creating a session" do
    post confirm_email_verification_url(token: "not-a-valid-token")

    assert_response :unprocessable_entity
    assert_equal 0, Session.count
    assert_nil @credential.reload.email_verified_at
    assert_nil response.cookies[EmailVerificationsController::SESSION_COOKIE_NAME.to_s]
  end

  test "POST rejects a token generated after the email was already verified" do
    @credential.update!(email_verified_at: Time.current)
    token = @credential.generate_token_for(:email_verification)

    post confirm_email_verification_url(token:)

    assert_response :unprocessable_entity
    assert_equal 0, Session.count
    assert_select "h1", "Verification link unavailable"
  end

  test "POST requires a CSRF token when forgery protection is enabled" do
    previous_setting = EmailVerificationsController.allow_forgery_protection
    EmailVerificationsController.allow_forgery_protection = true

    post confirm_email_verification_url(token: @token)

    assert_response :unprocessable_entity
    assert_equal 0, Session.count
    assert_nil @credential.reload.email_verified_at
  ensure
    EmailVerificationsController.allow_forgery_protection = previous_setting
  end
end
