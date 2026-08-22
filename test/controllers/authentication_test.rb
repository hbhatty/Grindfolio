require "test_helper"

class SessionRestorationProbeController < ApplicationController
  def show
    render plain: Current.session&.id.to_s
  end
end

class AuthenticationTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup { Current.reset }
  teardown { Current.reset }

  test "restores an active session without refreshing activity before the cadence" do
    starting_time = Time.utc(2026, 8, 21, 12)
    session, cookie = travel_to(starting_time) { create_session_cookie }
    last_seen_at = session.last_seen_at
    expires_at = session.expires_at

    travel_to starting_time + Session::ACTIVITY_REFRESH_CADENCE - 1.second do
      with_probe_route do
        get "/session_probe", headers: { "Cookie" => cookie }

        assert_response :success
        assert_equal session.id.to_s, response.body
        assert_session_cookie_not_rewritten
      end

      assert_nil Current.session
      assert_equal last_seen_at, session.reload.last_seen_at
      assert_equal expires_at, session.expires_at
    end
  end

  test "refreshes activity when the cadence has elapsed without extending the session or cookie" do
    starting_time = Time.utc(2026, 8, 21, 12)
    session, cookie = travel_to(starting_time) { create_session_cookie }
    expires_at = session.expires_at

    travel_to starting_time + Session::ACTIVITY_REFRESH_CADENCE do
      with_probe_route do
        get "/session_probe", headers: { "Cookie" => cookie }

        assert_response :success
        assert_equal session.id.to_s, response.body
        assert_session_cookie_not_rewritten
      end

      assert_nil Current.session
      assert_equal Time.current, session.reload.last_seen_at
      assert_equal expires_at, session.expires_at
    end
  end

  test "ignores missing and tampered cookies without deleting a valid session" do
    session, cookie = create_session_cookie

    with_probe_route do
      get "/session_probe"
      assert_response :success
      assert_equal "", response.body

      tampered_cookie = cookie.dup
      tampered_cookie[-1] = tampered_cookie[-1] == "a" ? "b" : "a"
      get "/session_probe", headers: { "Cookie" => tampered_cookie }
      assert_response :success
      assert_equal "", response.body
      assert_session_cookie_cleared
    end

    assert Session.exists?(session.id)
    assert_nil Current.session
  end

  test "clears a signed cookie for a nonexistent session without crashing" do
    session, cookie = create_session_cookie
    session.destroy!

    with_probe_route do
      get "/session_probe", headers: { "Cookie" => cookie }

      assert_response :success
      assert_equal "", response.body
      assert_session_cookie_cleared
    end

    assert_nil Current.session
  end

  test "deletes an idle-expired session and clears its cookie" do
    session, cookie = create_session_cookie
    session.update!(last_seen_at: 8.days.ago, expires_at: 1.day.from_now)

    with_probe_route do
      get "/session_probe", headers: { "Cookie" => cookie }

      assert_response :success
      assert_equal "", response.body
      assert_session_cookie_cleared
    end

    assert_not Session.exists?(session.id)
    assert_nil Current.session
  end

  test "deletes an absolutely expired session and clears its cookie" do
    session, cookie = create_session_cookie
    session.update!(last_seen_at: 2.days.ago, expires_at: 1.second.ago)

    with_probe_route do
      get "/session_probe", headers: { "Cookie" => cookie }

      assert_response :success
      assert_equal "", response.body
      assert_session_cookie_cleared
    end

    assert_not Session.exists?(session.id)
    assert_nil Current.session
  end

  private
    def assert_session_cookie_cleared
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")

      assert_match(/#{Regexp.escape(Session::COOKIE_NAME.to_s)}=;/, set_cookie)
      assert_match(/expires=Thu, 01 Jan 1970 00:00:00 GMT/i, set_cookie)
    end

    def assert_session_cookie_not_rewritten
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")

      refute_match(/#{Regexp.escape(Session::COOKIE_NAME.to_s)}=/, set_cookie)
    end

    def with_probe_route(&block)
      with_routing do |routes|
        routes.draw do
          get "/session_probe", to: "session_restoration_probe#show"
        end
        yield
      end
    end

    def create_session_cookie
      user = User.create!
      credential = user.create_password_credential!(
        email_address: "developer@example.com",
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
      token = credential.generate_token_for(:email_verification)

      post confirm_email_verification_path(token:)

      assert_redirected_to root_path
      session = user.sessions.sole
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
      cookie = set_cookie.lines.find { |line| line.start_with?("#{Session::COOKIE_NAME}=") }.split(";", 2).first
      [ session, cookie ]
    end
end
