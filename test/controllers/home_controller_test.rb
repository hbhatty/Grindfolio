require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup { Current.reset }
  teardown { Current.reset }

  test "renders the Gridfolio home page" do
    get root_url

    assert_response :success
    assert_select "h1", "Gridfolio"
    assert_select "p", "Your developer journey, mapped daily."
    assert_select "a[href='#{sign_up_path}']", "Create an account"
    assert_select "a[href='#{sign_in_path}']", "Sign in"
    assert_select "a[href='#{account_path}']", count: 0
    assert_select "form[action='#{sign_out_path}']", count: 0
    assert_select "p", text: "You are signed in.", count: 0
    assert_nil Current.session
  end

  test "renders the signed-in state for an active restored session" do
    user = User.create!
    credential = user.create_password_credential!(
      email_address: "developer@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
    token = credential.generate_token_for(:email_verification)

    post confirm_email_verification_url(token:)

    assert_redirected_to root_url
    assert_predicate user.sessions.sole, :active?

    get root_url

    assert_response :success
    assert_select "p", "You are signed in."
    assert_select "a[href='#{account_path}']", "Account"
    assert_select "a[href='#{sign_up_path}']", count: 0
    assert_select "a[href='#{sign_in_path}']", count: 0
    assert_select "form[action='#{sign_out_path}'][method='post']" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button", "Sign out"
    end
    assert_nil Current.session
  end
end
