require "test_helper"

class SignupsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PASSWORD = "correct horse battery staple"
  SIGNUP_COOKIE_NAME = EmailVerificationsController::SESSION_COOKIE_NAME.to_s

  setup do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  teardown do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  test "GET renders the accessible signup form" do
    get sign_up_url

    assert_response :success
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "h1", "Create your Grindfolio account"
    assert_select "form[action='#{sign_up_path}'][method='post']"
    assert_select "label[for='signup_email_address']", "Email address"
    assert_select "input[type='email'][name='signup[email_address]'][autocomplete='email'][required][maxlength='254']" do |inputs|
      inputs.each { |input| assert_nil input["size"] }
    end
    assert_select "label[for='signup_password']", "Password"
    assert_select "input[type='password'][name='signup[password]'][autocomplete='new-password'][required][minlength='8'][maxlength='72']" do |inputs|
      inputs.each { |input| assert_nil input["size"] }
    end
    assert_select "label[for='signup_password_confirmation']", "Confirm password"
    assert_select "input[type='password'][name='signup[password_confirmation]'][autocomplete='new-password'][required][minlength='8'][maxlength='72']" do |inputs|
      inputs.each { |input| assert_nil input["size"] }
    end
    assert_select "small#password-help", /72 bytes/
    assert_select "a[href='#{sign_in_path}']", "Sign in"
  end

  test "GET renders the check-email page without exposing an address or token" do
    get sign_up_success_url

    assert_response :success
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='signup-success-heading']"
    assert_select "h1#signup-success-heading", "Check your email"
    assert_select "a[href='#{new_email_verification_resend_path}']", "Request another verification email"
    assert_not_includes response.body, "developer@example.com"
    assert_no_verification_token_link
  end

  test "creates one user and credential, then queues verification mail after commit" do
    assert_difference -> { User.count }, 1 do
      assert_difference -> { PasswordCredential.count }, 1 do
        assert_enqueued_emails 1 do
          post sign_up_path, params: valid_params
        end
      end
    end

    assert_response :see_other
    assert_redirected_to sign_up_success_url
    follow_redirect!
    assert_response :success
    assert_select "h1", "Check your email"
    credential = PasswordCredential.order(:id).last
    assert_equal "developer@example.com", credential.email_address
    assert_nil credential.email_verified_at
    assert_equal 0, Session.where(user: credential.user).count
    assert_nil response.cookies[SIGNUP_COOKIE_NAME]
    assert_no_verification_token_link
  end

  test "renders validation errors, preserves normalized email, and clears password fields" do
    params = {
      signup: {
        email_address: "  Developer@Example.COM ",
        password: "too short",
        password_confirmation: "different password"
      }
    }

    assert_no_difference -> { User.count } do
      assert_no_difference -> { PasswordCredential.count } do
        assert_no_enqueued_emails do
          post sign_up_path, params:
        end
      end
    end

    assert_response :unprocessable_entity
    assert_select "input[name='signup[email_address]'][value='developer@example.com']"
    assert_select "input[type='password']" do |inputs|
      inputs.each { |input| assert_nil input["value"] }
    end
    assert_nil response.cookies[SIGNUP_COOKIE_NAME]
  end

  test "rejects a duplicate normalized email without creating an account or sending mail" do
    create_credential(email_address: "developer@example.com")

    assert_no_difference -> { User.count } do
      assert_no_difference -> { PasswordCredential.count } do
        assert_no_enqueued_emails do
          post sign_up_path, params: valid_params(email_address: "DEVELOPER@example.com")
        end
      end
    end

    assert_response :unprocessable_entity
    assert_select "li", /Email address has already been taken/
  end

  test "does not create an account without a valid CSRF token" do
    previous_setting = SignupsController.allow_forgery_protection
    SignupsController.allow_forgery_protection = true

    assert_no_difference -> { User.count } do
      assert_no_enqueued_emails do
        post sign_up_path, params: valid_params
      end
    end

    assert_response :unprocessable_entity
  ensure
    SignupsController.allow_forgery_protection = previous_setting
  end

  test "rate limits signup attempts by IP address" do
    invalid_params = {
      signup: {
        email_address: "not-an-email",
        password: "too short",
        password_confirmation: "too short"
      }
    }

    SignupsController::SIGNUP_RATE_LIMIT.times do
      post sign_up_path, params: invalid_params
      assert_response :unprocessable_entity
    end

    post sign_up_path, params: invalid_params

    assert_response :too_many_requests
    assert_select "a.auth-wordmark[href='#{root_path}']", "Grindfolio"
    assert_select "section[aria-labelledby='signup-rate-limit-heading']"
    assert_select "h1#signup-rate-limit-heading", "Please try again later"
    assert_select "a[href='#{sign_up_path}']", "Try signing up again"
  end

  private
    def assert_no_verification_token_link
      verification_links = css_select("a[href^='/email_verification/']").map { |link| link["href"] }

      assert_equal [ new_email_verification_resend_path ], verification_links
    end

    def valid_params(email_address: " Developer@Example.COM ")
      {
        signup: {
          email_address:,
          password: PASSWORD,
          password_confirmation: PASSWORD
        }
      }
    end

    def create_credential(email_address:)
      PasswordCredential.create!(
        user: User.create!,
        email_address:,
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
    end
end
