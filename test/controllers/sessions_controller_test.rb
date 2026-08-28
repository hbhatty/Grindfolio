require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    Rails.cache.clear
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "GET renders the accessible sign-in form" do
    get sign_in_url

    assert_response :success
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "h1", "Sign in to Grindfolio"
    assert_select "form[action='#{sign_in_path}'][method='post']"
    assert_select "label[for='session_email_address']", "Email address"
    assert_select "input[type='email'][name='session[email_address]'][autocomplete='email'][required][maxlength='254']" do |inputs|
      inputs.each { |input| assert_nil input["size"] }
    end
    assert_select "label[for='session_password']", "Password"
    assert_select "input[type='password'][name='session[password]'][autocomplete='current-password'][required][maxlength='72']" do |inputs|
      inputs.each do |input|
        assert_nil input["size"]
        assert_nil input["value"]
      end
    end
    assert_select "a[href='#{sign_up_path}']", "Create an account"
  end

  test "authenticates a verified credential after normalizing the email" do
    user, credential = create_credential(email_address: "developer@example.com", verified: true)

    assert_difference -> { Session.count }, 1 do
      post sign_in_path,
        params: login_params(email_address: "  DEVELOPER@EXAMPLE.COM "),
        headers: { "User-Agent" => "SessionsControllerTest" }
    end

    assert_response :see_other
    assert_redirected_to root_url
    session = user.sessions.sole
    assert_equal credential.user_id, session.user_id
    assert_equal "SessionsControllerTest", session.user_agent
    assert_not_nil session.ip_address
    assert_session_cookie_set(session)
  end

  test "missing, wrong, and unverified credentials share one generic failure" do
    create_credential(email_address: "developer@example.com", verified: true)
    create_credential(email_address: "unverified@example.com", verified: false)

    attempts = [
      login_params(email_address: ""),
      login_params(email_address: "developer@example.com", password: "wrong password"),
      login_params(email_address: "unverified@example.com")
    ]

    attempts.each do |params|
      assert_no_difference -> { Session.count } do
        post sign_in_path, params:
      end

      assert_response :unprocessable_entity
      assert_select "[role='alert']", text: "Invalid email address or password."
      assert_no_session_cookie_set
    end
  end

  test "an authenticated user is redirected without creating a duplicate session" do
    user, = create_credential(email_address: "developer@example.com", verified: true)

    post sign_in_path, params: login_params
    assert_response :see_other
    cookie = session_cookie_from_response
    assert_equal 1, user.sessions.count

    get sign_in_path, headers: { "Cookie" => cookie }

    assert_redirected_to root_url
    assert_equal 1, user.sessions.count

    post sign_in_path, params: login_params, headers: { "Cookie" => cookie }

    assert_response :see_other
    assert_redirected_to root_url
    assert_equal 1, user.sessions.count
  end

  test "rate limits sign-in attempts by IP address" do
    invalid_params = login_params(email_address: "not-an-email", password: "wrong password")

    SessionsController::LOGIN_RATE_LIMIT.times do
      post sign_in_path, params: invalid_params
      assert_response :unprocessable_entity
    end

    post sign_in_path, params: invalid_params

    assert_response :too_many_requests
    assert_select "h1", "Please try again later"
  end

  test "signing in requires a CSRF token when forgery protection is enabled" do
    create_credential(email_address: "developer@example.com", verified: true)
    previous_setting = SessionsController.allow_forgery_protection
    SessionsController.allow_forgery_protection = true

    assert_no_difference -> { Session.count } do
      post sign_in_path, params: login_params
    end

    assert_response :unprocessable_entity
  ensure
    SessionsController.allow_forgery_protection = previous_setting
  end

  test "signing out deletes only the current session and clears its cookie" do
    user, = create_credential(email_address: "developer@example.com", verified: true)
    post sign_in_path, params: login_params
    cookie = session_cookie_from_response
    current_session = user.sessions.sole
    other_session = user.sessions.create!

    delete sign_out_path, headers: { "Cookie" => cookie }

    assert_response :see_other
    assert_redirected_to root_url
    assert_not Session.exists?(current_session.id)
    assert Session.exists?(other_session.id)
    assert_session_cookie_cleared
  end

  test "signing out while already signed out is safe" do
    assert_no_difference -> { Session.count } do
      delete sign_out_path
    end

    assert_response :see_other
    assert_redirected_to root_url
    assert_empty Array(response.headers["Set-Cookie"])
  end

  test "signing out requires a CSRF token when forgery protection is enabled" do
    user, = create_credential(email_address: "developer@example.com", verified: true)
    post sign_in_path, params: login_params
    cookie = session_cookie_from_response
    session = user.sessions.sole

    previous_setting = SessionsController.allow_forgery_protection
    SessionsController.allow_forgery_protection = true

    delete sign_out_path, headers: { "Cookie" => cookie }

    assert_response :unprocessable_entity
    assert Session.exists?(session.id)
  ensure
    SessionsController.allow_forgery_protection = previous_setting
  end

  private
    def create_credential(email_address:, verified:)
      user = User.create!
      credential = user.create_password_credential!(
        email_address:,
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
      credential.update!(email_verified_at: Time.current) if verified
      [ user, credential ]
    end

    def login_params(email_address: "developer@example.com", password: PASSWORD)
      {
        session: {
          email_address:,
          password:
        }
      }
    end

    def session_cookie_from_response
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
      line = set_cookie.lines.find { |entry| entry.start_with?("#{Session::COOKIE_NAME}=") }
      line.split(";", 2).first
    end

    def assert_session_cookie_set(session)
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")

      assert_match(/#{Regexp.escape(Session::COOKIE_NAME.to_s)}=[^;]+--/, set_cookie)
      assert_match(/httponly/i, set_cookie)
      assert_match(/samesite=lax/i, set_cookie)
      assert_not_includes set_cookie, "Secure"
      assert_equal session.expires_at.to_i, set_cookie.match(/expires=([^;]+)/i).then { |match| Time.httpdate(match[1]).to_i }
    end

    def assert_no_session_cookie_set
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")

      assert_not_includes set_cookie, "#{Session::COOKIE_NAME}="
    end

    def assert_session_cookie_cleared
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")

      assert_match(/#{Regexp.escape(Session::COOKIE_NAME.to_s)}=;/, set_cookie)
      assert_match(/expires=Thu, 01 Jan 1970 00:00:00 GMT/i, set_cookie)
    end
end
