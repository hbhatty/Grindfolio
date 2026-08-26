require "test_helper"
require "base64"

class Notion::ExchangeAuthorizationCodeTest < ActiveSupport::TestCase
  class FakeHttp
    attr_reader :request

    def initialize(response)
      @response = response
    end

    def start(*)
      client = Object.new
      response = @response
      client.define_singleton_method(:request) do |request|
        @captured_request = request
        response
      end
      result = yield(client)
      @request = client.instance_variable_get(:@captured_request)
      result
    end
  end

  test "exchanges the code with HTTP Basic authentication and normalizes the authorization" do
    http = FakeHttp.new(success_response)

    authorization = exchange(http:)

    assert_equal "new-access-token", authorization.fetch(:access_token)
    assert_equal "new-refresh-token", authorization.fetch(:refresh_token)
    assert_equal "bot-id", authorization.fetch(:bot_id)
    assert_equal "workspace-id", authorization.fetch(:workspace_id)
    assert_equal "Example workspace", authorization.fetch(:workspace_name)
    assert_equal "notion-user-id", authorization.fetch(:owner_user_id)
    assert_equal "Basic #{Base64.strict_encode64("client-id:client-secret")}", http.request["Authorization"]
    assert_equal "2026-03-11", http.request["Notion-Version"]
    assert_equal(
      {
        "grant_type" => "authorization_code",
        "code" => "authorization-code",
        "redirect_uri" => "http://example.test/auth/notion/callback"
      },
      JSON.parse(http.request.body)
    )
  end

  test "rejects a response without a renewable credential pair" do
    response = json_response(success_payload.merge(refresh_token: nil))

    assert_raises Notion::ExchangeAuthorizationCode::Error do
      exchange(http: FakeHttp.new(response))
    end
  end

  test "rejects a provider failure without exposing its response" do
    response = json_response({ error: "invalid_grant", secret: "provider-secret" }, code: "400")

    error = assert_raises Notion::ExchangeAuthorizationCode::Error do
      exchange(http: FakeHttp.new(response))
    end

    assert_equal "Notion authorization could not be completed", error.message
    assert_not_includes error.message, "provider-secret"
  end

  private
    def exchange(http:)
      Notion::ExchangeAuthorizationCode.new(
        code: "authorization-code",
        redirect_uri: "http://example.test/auth/notion/callback",
        client_id: "client-id",
        client_secret: "client-secret",
        http:
      ).call
    end

    def success_response
      json_response(success_payload)
    end

    def success_payload
      {
        access_token: "new-access-token",
        refresh_token: "new-refresh-token",
        bot_id: "bot-id",
        workspace_id: "workspace-id",
        workspace_name: "Example workspace",
        owner: {
          type: "user",
          user: { id: "notion-user-id" }
        }
      }
    end

    def json_response(body, code: "200")
      response_class = code == "200" ? Net::HTTPOK : Net::HTTPBadRequest
      response = response_class.new("1.1", code, "Response")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate(body)
      response
    end
end
