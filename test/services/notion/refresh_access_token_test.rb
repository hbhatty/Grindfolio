require "test_helper"
require "base64"

class Notion::RefreshAccessTokenTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :request

    def initialize(response)
      @response = response
    end

    def start(*)
      response = @response
      client = Object.new
      client.define_singleton_method(:request) do |request|
        @captured_request = request
        response
      end
      result = yield(client)
      @request = client.instance_variable_get(:@captured_request)
      result
    end
  end

  setup do
    @connection = User.create!.create_notion_connection!(
      workspace_id: "workspace-id",
      workspace_name: "Example workspace",
      bot_id: "bot-id",
      owner_user_id: "owner-user-id",
      access_token: "old-access-token",
      refresh_token: "old-refresh-token",
      tracking_started_on: Date.new(2026, 8, 26),
      authorized_at: Time.utc(2026, 8, 26, 16)
    )
  end

  test "atomically rotates the renewable credential pair" do
    http = FakeHttp.new(
      json_response({ access_token: "new-access-token", refresh_token: "new-refresh-token" })
    )

    access_token = refresher(http:).call

    assert_equal "new-access-token", access_token
    assert_equal "new-access-token", @connection.reload.access_token
    assert_equal "new-refresh-token", @connection.refresh_token
    assert_equal "Basic #{Base64.strict_encode64("client-id:client-secret")}", http.request["Authorization"]
    assert_equal(
      { "grant_type" => "refresh_token", "refresh_token" => "old-refresh-token" },
      JSON.parse(http.request.body)
    )
  end

  test "requires reauthorization when Notion rejects the refresh token" do
    http = FakeHttp.new(json_response({ error: "invalid_grant" }, code: "400"))

    assert_raises Notion::RefreshAccessToken::ReauthorizationRequired do
      refresher(http:).call
    end

    assert_equal "old-access-token", @connection.reload.access_token
    assert_equal "old-refresh-token", @connection.refresh_token
  end

  private
    def refresher(http:)
      Notion::RefreshAccessToken.new(
        connection: @connection,
        client_id: "client-id",
        client_secret: "client-secret",
        http:
      )
    end

    def json_response(body, code: "200")
      response_class = code == "200" ? Net::HTTPOK : Net::HTTPBadRequest
      response = response_class.new("1.1", code, "Response")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate(body)
      response
    end
end
