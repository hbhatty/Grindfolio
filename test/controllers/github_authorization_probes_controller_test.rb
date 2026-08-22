require "test_helper"

class GithubAuthorizationProbesControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = authorization
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
    Current.reset
  end

  test "requires a signed-in Gridfolio account" do
    begin_github_authorization
    follow_redirect!

    assert_response :see_other
    assert_redirected_to sign_in_path
  end

  test "renders only sanitized identity token metadata and contribution results" do
    sign_in_as(create_verified_user)
    result = probe_result
    fake_probe_class = Class.new do
      define_method(:initialize) { |access_token:| @access_token = access_token }
      define_method(:call) { result }
    end
    fake_probe_class.const_set(:Error, Github::ContributionProbe::Error)

    stub_const(Github, :ContributionProbe, fake_probe_class) do
      assert_no_changes -> { [ User.count, PasswordCredential.count, Session.count ] } do
        begin_github_authorization
        follow_redirect!
      end
    end

    assert_response :success
    assert_select "h1", "GitHub authorization succeeded"
    assert_select "dd", "octocat"
    assert_select "dd", "42"
    assert_select "dd", text: "Yes", count: 2
    assert_select "dd", "none"
    assert_select "table tbody tr", count: 1
    assert_not_includes response.body, "access-token"
    assert_not_includes response.body, "refresh-token"
  end

  test "handles a missing authorization without exposing callback parameters" do
    sign_in_as(create_verified_user)

    get github_authorization_failure_path, params: { message: "temporary-code" }

    assert_response :unprocessable_entity
    assert_select "h1", "GitHub authorization was not completed"
    assert_not_includes response.body, "temporary-code"
  end

  private
    def begin_github_authorization
      post "/auth/github"
      assert_redirected_to github_authorization_probe_path
    end

    def create_verified_user
      user = User.create!
      user.create_password_credential!(
        email_address: "developer@example.com",
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

    def authorization
      OmniAuth::AuthHash.new(
        uid: "42",
        info: { nickname: "octocat" },
        credentials: {
          token: "access-token",
          refresh_token: "refresh-token",
          expires: true,
          expires_at: Time.utc(2026, 8, 22, 20).to_i,
          scope: ""
        }
      )
    end

    def probe_result
      {
        github_login: "octocat",
        github_database_id: 42,
        github_node_id: "MDQ6VXNlcjQy",
        started_at: "2026-07-24T00:00:00Z",
        ended_at: "2026-08-22T23:59:59Z",
        total_contributions: 2,
        restricted_contributions: 0,
        days: [ { "date" => "2026-08-22", "contributionCount" => 2 } ],
        rate_limit: { "cost" => 1, "remaining" => 4_999 }
      }
    end
end
