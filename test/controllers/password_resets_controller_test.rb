require "test_helper"

class PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"
  REPLACEMENT_PASSWORD = "new correct horse battery staple"

  setup do
    @user = User.create!
    @credential = PasswordCredential.create!(
      user: @user,
      email_address: "developer@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD,
      email_verified_at: Time.current
    )
    @token = @credential.generate_token_for(:password_reset)
  end

  test "GET validates the token and renders an accessible new-password form without changing state" do
    session = @user.sessions.create!

    get password_reset_url(token: @token)

    assert_response :success
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='password-reset-heading']"
    assert_select "h1#password-reset-heading", "Choose a new password"
    assert_select "p", /other Grindfolio sessions will be signed out/
    assert_select "form[action='#{password_reset_path(token: @token)}'][method='post']"
    assert_select "input[name='_method'][value='patch']"
    assert_select "label[for='password_reset_password']", "New password"
    assert_select "input[type='password'][name='password_reset[password]'][autocomplete='new-password'][required][minlength='8'][maxlength='72'][autofocus][aria-describedby='reset-password-help']" do |inputs|
      inputs.each do |input|
        assert_nil input["size"]
        assert_nil input["value"]
      end
    end
    assert_select "label[for='password_reset_password_confirmation']", "Confirm new password"
    assert_select "input[type='password'][name='password_reset[password_confirmation]'][autocomplete='new-password'][required][minlength='8'][maxlength='72']"

    assert @credential.reload.authenticate(PASSWORD)
    assert session.reload.active?
    assert_equal @credential, PasswordCredential.find_by_token_for(:password_reset, @token)
  end

  test "invalid and expired tokens render one recovery response" do
    get password_reset_url(token: "invalid")

    assert_response :unprocessable_entity
    assert_invalid_link_response

    travel_to(PasswordCredential::PASSWORD_RESET_TOKEN_LIFETIME.from_now + 1.second) do
      get password_reset_url(token: @token)

      assert_response :unprocessable_entity
      assert_invalid_link_response
    end
  end

  test "invalid replacement passwords preserve the old password sessions and reset token" do
    session = @user.sessions.create!

    assert_no_difference -> { @user.sessions.count } do
      patch password_reset_path(token: @token), params: {
        password_reset: {
          password: "short",
          password_confirmation: "different"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".form-message[role='alert']", /Check the form/
    assert_select ".form-message li", /Password is too short/
    assert_select ".form-message li", /Password confirmation doesn't match Password/
    assert @credential.reload.authenticate(PASSWORD)
    assert session.reload.active?
    assert_equal @credential, PasswordCredential.find_by_token_for(:password_reset, @token)
  end

  test "successful reset changes the password revokes every session clears the cookie and requires fresh login" do
    post sign_in_path, params: {
      session: {
        email_address: @credential.email_address,
        password: PASSWORD
      }
    }
    assert_response :see_other
    @user.sessions.create!(ip_address: "203.0.113.10", user_agent: "Other browser")
    assert_equal 2, @user.sessions.count

    patch password_reset_path(token: @token), params: {
      password_reset: {
        password: REPLACEMENT_PASSWORD,
        password_confirmation: REPLACEMENT_PASSWORD
      }
    }

    assert_response :see_other
    assert_redirected_to sign_in_url
    assert_session_cookie_cleared
    assert_empty @user.sessions.reload
    assert_not @credential.reload.authenticate(PASSWORD)
    assert @credential.authenticate(REPLACEMENT_PASSWORD)
    assert_nil PasswordCredential.find_by_token_for(:password_reset, @token)

    follow_redirect!
    assert_select ".flash-message--notice[role='status']", /password has been reset/

    post sign_in_path, params: {
      session: {
        email_address: @credential.email_address,
        password: PASSWORD
      }
    }
    assert_response :unprocessable_entity
    assert_empty @user.sessions.reload

    post sign_in_path, params: {
      session: {
        email_address: @credential.email_address,
        password: REPLACEMENT_PASSWORD
      }
    }
    assert_response :see_other
    assert_equal 1, @user.sessions.reload.size
  end

  test "replaying a used token cannot change the password or revoke a newer session" do
    patch password_reset_path(token: @token), params: {
      password_reset: {
        password: REPLACEMENT_PASSWORD,
        password_confirmation: REPLACEMENT_PASSWORD
      }
    }
    assert_response :see_other

    new_session = @user.sessions.create!

    patch password_reset_path(token: @token), params: {
      password_reset: {
        password: "attacker chosen password",
        password_confirmation: "attacker chosen password"
      }
    }

    assert_response :unprocessable_entity
    assert_invalid_link_response
    assert @credential.reload.authenticate(REPLACEMENT_PASSWORD)
    assert_not @credential.authenticate("attacker chosen password")
    assert_equal [ new_session.id ], @user.sessions.reload.ids
  end

  test "resetting another account does not revoke the currently signed-in account" do
    other_user = User.create!
    other_credential = PasswordCredential.create!(
      user: other_user,
      email_address: "other-developer@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD,
      email_verified_at: Time.current
    )
    @user.sessions.create!

    post sign_in_path, params: {
      session: {
        email_address: other_credential.email_address,
        password: PASSWORD
      }
    }
    assert_response :see_other
    other_session = other_user.sessions.sole

    patch password_reset_path(token: @token), params: {
      password_reset: {
        password: REPLACEMENT_PASSWORD,
        password_confirmation: REPLACEMENT_PASSWORD
      }
    }

    assert_response :see_other
    assert_redirected_to root_url
    assert_empty @user.sessions.reload
    assert_equal [ other_session.id ], other_user.sessions.reload.ids
    assert_not_includes Array(response.headers["Set-Cookie"]).join("\n"), "#{Session::COOKIE_NAME}=;"
    assert @credential.reload.authenticate(REPLACEMENT_PASSWORD)

    follow_redirect!
    assert_select "button", "Sign out"
    assert_select ".flash-message--notice[role='status']", /Sign out before signing in/
  end

  test "password update requires a valid CSRF token" do
    previous_setting = PasswordResetsController.allow_forgery_protection
    PasswordResetsController.allow_forgery_protection = true

    assert_no_difference -> { @user.sessions.count } do
      patch password_reset_path(token: @token), params: {
        password_reset: {
          password: REPLACEMENT_PASSWORD,
          password_confirmation: REPLACEMENT_PASSWORD
        }
      }
    end

    assert_response :unprocessable_entity
    assert @credential.reload.authenticate(PASSWORD)
    assert_equal @credential, PasswordCredential.find_by_token_for(:password_reset, @token)
  ensure
    PasswordResetsController.allow_forgery_protection = previous_setting
  end

  private
    def assert_invalid_link_response
      assert_select "section[aria-labelledby='invalid-password-reset-heading']"
      assert_select "h1#invalid-password-reset-heading", "Password-reset link unavailable"
      assert_select "p", /invalid, expired, or has already been used/
      assert_select "a[href='#{new_password_reset_request_path}']", "Request another reset email"
    end

    def assert_session_cookie_cleared
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")

      assert_match(/#{Regexp.escape(Session::COOKIE_NAME.to_s)}=;/, set_cookie)
      assert_match(/expires=Thu, 01 Jan 1970 00:00:00 GMT/i, set_cookie)
    end
end
