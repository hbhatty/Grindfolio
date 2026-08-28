require "test_helper"

class LeetcodeVerificationsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    Rails.cache.clear
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "requires authentication before generating a challenge" do
    assert_no_difference "LeetcodeVerificationChallenge.count" do
      post leetcode_verification_path,
        params: { leetcode_verification: { username: "exampleuser" } }
    end

    assert_response :see_other
    assert_redirected_to sign_in_path
  end

  test "generates a local challenge without creating a connection" do
    user = create_verified_user
    sign_in_as(user)

    assert_difference "LeetcodeVerificationChallenge.count", 1 do
      assert_no_difference "LeetcodeConnection.count" do
        post leetcode_verification_path,
          params: { leetcode_verification: { username: "  exampleuser  " } }
      end
    end

    challenge = user.leetcode_verification_challenges.find_by!(consumed_at: nil)
    assert_response :see_other
    assert_redirected_to account_path
    assert_equal "Your temporary LeetCode verification challenge is ready.", flash[:notice]
    assert_equal "exampleuser", challenge.requested_username
    assert_match(/\Agrindfolio-verify-[0-9a-f]{24}\z/, challenge.token)
    assert_in_delta 15.minutes.from_now, challenge.expires_at, 2.seconds
  end

  test "verifies the current challenge through an explicit provider request" do
    now = Time.utc(2026, 8, 24, 4, 30)

    travel_to now do
      user = create_verified_user
      challenge = LeetcodeVerificationChallenge.issue_for!(
        user:,
        requested_username: "exampleuser"
      )
      sign_in_as(user)
      calls = 0
      profile_client = Object.new
      profile_client.define_singleton_method(:call) do
        calls += 1
        Leetcode::PublicProfile::Result.new(
          username: "ExampleUser",
          about_me: "Profile text\n#{challenge.token}"
        )
      end
      original_profile_factory = Leetcode::PublicProfile.method(:new)
      requested_username = nil
      profile_factory = lambda do |username:|
        requested_username = username
        profile_client
      end

      begin
        Leetcode::PublicProfile.define_singleton_method(:new, profile_factory)
        assert_difference "LeetcodeConnection.count", 1 do
          post verify_leetcode_verification_path
        end
      ensure
        Leetcode::PublicProfile.define_singleton_method(:new, original_profile_factory)
      end
      assert_equal "exampleuser", requested_username

      connection = user.reload.leetcode_connection
      assert_response :see_other
      assert_redirected_to account_path
      assert_equal "LeetCode account @ExampleUser is connected. Practice tracking starts today in UTC.", flash[:notice]
      assert_equal Date.new(2026, 8, 24), connection.tracking_started_on
      assert_equal now, connection.verified_at
      assert_equal now, challenge.reload.consumed_at
      assert_equal 1, calls
    end
  end

  test "replaces an earlier unconsumed challenge for the current user only" do
    current_user = create_verified_user(email_address: "current@example.com")
    other_user = create_verified_user(email_address: "other@example.com")
    previous = LeetcodeVerificationChallenge.issue_for!(
      user: current_user,
      requested_username: "old-user"
    )
    other_challenge = LeetcodeVerificationChallenge.issue_for!(
      user: other_user,
      requested_username: "other-user"
    )
    sign_in_as(current_user)

    assert_no_difference "LeetcodeVerificationChallenge.count" do
      post leetcode_verification_path,
        params: { leetcode_verification: { username: "new-user" } }
    end

    assert_not LeetcodeVerificationChallenge.exists?(previous.id)
    assert LeetcodeVerificationChallenge.exists?(other_challenge.id)
    assert_equal "new-user", current_user.leetcode_verification_challenges.find_by!(consumed_at: nil).requested_username
  end

  test "rejects a profile URL without replacing the current challenge" do
    user = create_verified_user
    existing = LeetcodeVerificationChallenge.issue_for!(user:, requested_username: "exampleuser")
    sign_in_as(user)

    assert_no_changes -> { user.leetcode_verification_challenges.pluck(:id) } do
      post leetcode_verification_path,
        params: {
          leetcode_verification: {
            username: "https://leetcode.com/u/exampleuser/"
          }
        }
    end

    assert_response :see_other
    assert_redirected_to account_path
    assert_includes flash[:alert], "must be a LeetCode username"
    assert LeetcodeVerificationChallenge.exists?(existing.id)
  end

  test "does not issue another challenge for a connected user" do
    user = create_verified_user
    user.create_leetcode_connection!(
      username: "exampleuser",
      tracking_started_on: Date.new(2026, 8, 24),
      verified_at: Time.current
    )
    sign_in_as(user)

    assert_no_difference "LeetcodeVerificationChallenge.count" do
      post leetcode_verification_path,
        params: { leetcode_verification: { username: "another-user" } }
    end

    assert_response :see_other
    assert_redirected_to account_path
    assert_equal "Your LeetCode account is already connected.", flash[:notice]
  end

  test "rate limits verification attempts without making a provider request" do
    sign_in_as(create_verified_user)

    10.times do |attempt|
      post leetcode_verification_path,
        params: { leetcode_verification: { username: "example-user-#{attempt}" } }
      assert_response :see_other
    end

    post leetcode_verification_path,
      params: { leetcode_verification: { username: "example-user-final" } }

    assert_response :too_many_requests
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='rate-limit-heading']"
    assert_select "h1#rate-limit-heading", "Wait before trying again"
    assert_select "p", /No provider request was made/
    assert_select "a[href='#{account_path}']", "Return to your account"
  end

  test "challenge generation requires a CSRF token when forgery protection is enabled" do
    user = create_verified_user
    sign_in_as(user)
    previous_setting = LeetcodeVerificationsController.allow_forgery_protection
    LeetcodeVerificationsController.allow_forgery_protection = true

    assert_no_difference "LeetcodeVerificationChallenge.count" do
      post leetcode_verification_path,
        params: { leetcode_verification: { username: "exampleuser" } }
    end

    assert_response :unprocessable_entity
  ensure
    LeetcodeVerificationsController.allow_forgery_protection = previous_setting
  end

  private
    def create_verified_user(email_address: "developer@example.com")
      user = User.create!
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
