require "test_helper"

class GithubConnectionsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    Rails.cache.clear
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = authorization
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
    Current.reset
    Rails.cache.clear
  end

  test "requires a signed-in Grindfolio account" do
    assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        begin_github_authorization
        follow_redirect!
      end
    end

    assert_response :see_other
    assert_redirected_to sign_in_path
  end

  test "connects GitHub without saving contribution data" do
    user = create_verified_user
    sign_in_as(user)

    assert_difference -> { ExternalIdentity.count } => 1,
      -> { GithubConnection.count } => 1 do
      assert_no_difference -> { GithubDailyContribution.count } do
        begin_github_authorization
        follow_redirect!
      end
    end

    assert_response :see_other
    assert_redirected_to account_path
    connection = user.external_identities.github.first.github_connection
    assert_equal "octocat", connection.external_identity.provider_username
    assert_equal "access-token", connection.access_token
    assert_equal "refresh-token", connection.refresh_token
    assert_predicate connection, :sync_status_pending?
    assert_equal "GitHub connected as octocat.", flash[:notice]
    assert_not_includes response.body, "access-token"
    assert_not_includes response.body, "refresh-token"
  end

  test "reauthorizes the same GitHub account without creating duplicates" do
    user = create_verified_user
    sign_in_as(user)
    begin_github_authorization
    follow_redirect!
    original_connection = user.external_identities.github.first.github_connection
    original_tracking_date = original_connection.tracking_started_on
    OmniAuth.config.mock_auth[:github] = authorization(
      nickname: "renamed-octocat",
      access_token: "replacement-access-token",
      refresh_token: "replacement-refresh-token"
    )

    assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        begin_github_authorization
        follow_redirect!
      end
    end

    original_connection.reload
    assert_equal original_tracking_date, original_connection.tracking_started_on
    assert_equal "renamed-octocat", original_connection.external_identity.provider_username
    assert_equal "replacement-access-token", original_connection.access_token
    assert_equal "replacement-refresh-token", original_connection.refresh_token
  end

  test "does not claim a GitHub account connected to another user" do
    owner = create_verified_user(email_address: "owner@example.com")
    sign_in_as(owner)
    begin_github_authorization
    follow_redirect!
    delete sign_out_path

    other_user = create_verified_user(email_address: "other@example.com")
    sign_in_as(other_user)

    assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        begin_github_authorization
        follow_redirect!
      end
    end

    assert_response :unprocessable_entity
    assert_select "h1", "GitHub connection was not completed"
    assert_empty other_user.external_identities
  end

  test "handles a missing authorization without saving or exposing callback parameters" do
    sign_in_as(create_verified_user)

    assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        get github_connection_failure_path, params: { message: "temporary-code" }
      end
    end

    assert_response :unprocessable_entity
    assert_select "h1", "GitHub connection was not completed"
    assert_not_includes response.body, "temporary-code"
  end

  test "handles a structurally incomplete authorization without creating partial records" do
    sign_in_as(create_verified_user)
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      uid: "42",
      credentials: {
        token: "access-token",
        refresh_token: "refresh-token",
        expires_at: Time.utc(2026, 8, 22, 20).to_i
      }
    )

    assert_no_difference -> { ExternalIdentity.count } do
      assert_no_difference -> { GithubConnection.count } do
        begin_github_authorization
        follow_redirect!
      end
    end

    assert_response :unprocessable_entity
    assert_select "h1", "GitHub connection was not completed"
    assert_not_includes response.body, "access-token"
    assert_not_includes response.body, "refresh-token"
  end

  private
    def begin_github_authorization
      post "/auth/github"
      assert_redirected_to github_connection_callback_path
    end

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
    end

    def authorization(
      nickname: "octocat",
      access_token: "access-token",
      refresh_token: "refresh-token"
    )
      OmniAuth::AuthHash.new(
        uid: "42",
        info: {
          nickname:,
          email: "octocat@example.com",
          image: "https://example.com/octocat.png"
        },
        credentials: {
          token: access_token,
          refresh_token:,
          expires: true,
          expires_at: Time.utc(2026, 8, 22, 20).to_i
        }
      )
    end
end
