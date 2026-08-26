require "test_helper"

class NotionConnectionsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"

  setup do
    Current.reset
    Rails.cache.clear
    @authorization_exchange = NotionConnectionsController.authorization_exchange
  end

  teardown do
    Current.reset
    Rails.cache.clear
    NotionConnectionsController.authorization_exchange = @authorization_exchange
  end

  test "requires a signed-in Grindfolio account" do
    post notion_authorization_path

    assert_response :see_other
    assert_redirected_to sign_in_path
  end

  test "starts Notion OAuth with a state token bound to the current session" do
    user = create_verified_user
    sign_in_as(user)

    post notion_authorization_path

    assert_response :redirect
    authorization_uri = URI(response.location)
    query = URI.decode_www_form(authorization_uri.query).to_h
    assert_equal "api.notion.com", authorization_uri.host
    assert_equal "/v1/oauth/authorize", authorization_uri.path
    assert_equal "user", query.fetch("owner")
    assert_equal "test-notion-client-id", query.fetch("client_id")
    assert_equal notion_connection_callback_url, query.fetch("redirect_uri")
    assert_equal "code", query.fetch("response_type")
    assert Notion::OauthState.verify!(token: query.fetch("state"), session: user.sessions.last)
  end

  test "connects the current user without synchronizing application data" do
    user = create_verified_user
    sign_in_as(user)
    state = begin_notion_authorization
    exchange_arguments = nil
    exchange = lambda do |**arguments|
      exchange_arguments = arguments
      authorization
    end

    NotionConnectionsController.authorization_exchange = exchange
    assert_difference -> { NotionConnection.count }, 1 do
      get notion_connection_callback_path, params: { code: "authorization-code", state: }
    end

    assert_response :see_other
    assert_redirected_to account_path
    assert_equal "Notion connected to Example workspace.", flash[:notice]
    assert_equal "authorization-code", exchange_arguments.fetch(:code)
    assert_equal notion_connection_callback_url, exchange_arguments.fetch(:redirect_uri)
    connection = user.reload.notion_connection
    assert_equal "workspace-id", connection.workspace_id
    assert_equal "bot-id", connection.bot_id
    assert_equal "access-token", connection.access_token
    assert_equal "refresh-token", connection.refresh_token
  end

  test "rejects an invalid state before exchanging the authorization code" do
    user = create_verified_user
    sign_in_as(user)
    exchange = ->(**) { flunk "authorization code must not be exchanged" }

    NotionConnectionsController.authorization_exchange = exchange
    assert_no_difference -> { NotionConnection.count } do
      get notion_connection_callback_path,
        params: { code: "authorization-code", state: "invalid-state" }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Notion could not be connected"
  end

  test "handles provider denial without saving or exposing callback parameters" do
    user = create_verified_user
    sign_in_as(user)
    state = begin_notion_authorization
    exchange = ->(**) { flunk "denied authorization must not be exchanged" }

    NotionConnectionsController.authorization_exchange = exchange
    assert_no_difference -> { NotionConnection.count } do
      get notion_connection_callback_path,
        params: {
          error: "access_denied",
          error_description: "provider-secret-description",
          state:
        }
    end

    assert_response :unprocessable_entity
    assert_not_includes response.body, "provider-secret-description"
    assert_select "h1", "Notion could not be connected"
  end

  test "starting authorization requires a CSRF token when forgery protection is enabled" do
    user = create_verified_user
    sign_in_as(user)
    previous_setting = NotionConnectionsController.allow_forgery_protection
    NotionConnectionsController.allow_forgery_protection = true

    assert_no_difference -> { NotionConnection.count } do
      post notion_authorization_path
    end

    assert_response :unprocessable_entity
  ensure
    NotionConnectionsController.allow_forgery_protection = previous_setting
  end

  private
    def begin_notion_authorization
      post notion_authorization_path
      assert_response :redirect
      URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
    end

    def authorization
      {
        access_token: "access-token",
        refresh_token: "refresh-token",
        bot_id: "bot-id",
        workspace_id: "workspace-id",
        workspace_name: "Example workspace",
        owner_user_id: "notion-user-id"
      }
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
end
