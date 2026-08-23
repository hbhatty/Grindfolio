require "test_helper"

class Github::AccessTokenTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 8, 23, 12)

  class FakeHttp
    attr_reader :request, :starts

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @starts = 0
    end

    def start(*)
      @starts += 1
      raise @error if @error

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

  setup do
    user = User.create!
    identity = user.external_identities.create!(
      provider: "github",
      provider_uid: "42",
      provider_username: "octocat"
    )
    @connection = identity.create_github_connection!(
      tracking_started_on: Date.new(2026, 8, 23),
      access_token: "old-access-token",
      refresh_token: "old-refresh-token",
      access_token_expires_at: NOW + 4.minutes
    )
  end

  test "returns an access token that remains valid beyond the refresh margin" do
    @connection.update!(access_token_expires_at: NOW + 6.minutes)
    http = FakeHttp.new

    token = access_token(http:).call

    assert_equal "old-access-token", token
    assert_equal 0, http.starts
  end

  test "rotates and encrypts both tokens before the access token expires" do
    http = FakeHttp.new(response: success_response)

    token = access_token(http:).call

    assert_equal "new-access-token", token
    assert_equal "new-access-token", @connection.reload.access_token
    assert_equal "new-refresh-token", @connection.refresh_token
    assert_equal NOW + 8.hours, @connection.access_token_expires_at
    assert_equal NOW + 15_897_600.seconds, @connection.refresh_token_expires_at
    assert_equal "refresh_token", request_parameters(http).fetch("grant_type")
    assert_equal "old-refresh-token", request_parameters(http).fetch("refresh_token")
    assert_equal "test-client-id", request_parameters(http).fetch("client_id")
    assert_equal "application/json", http.request["Accept"]
    assert_not_equal "new-access-token", raw_database_value("access_token")
    assert_not_equal "new-refresh-token", raw_database_value("refresh_token")
  end

  test "requires reauthorization without making a request when refresh expiry is known" do
    @connection.update!(refresh_token_expires_at: NOW)
    http = FakeHttp.new

    assert_raises Github::AccessToken::ReauthorizationRequired do
      access_token(http:).call
    end

    assert_equal 0, http.starts
    assert_equal "old-access-token", @connection.reload.access_token
  end

  test "requires reauthorization when GitHub rejects the refresh token" do
    http = FakeHttp.new(response: json_response({ error: "bad_refresh_token" }))

    error = assert_raises Github::AccessToken::ReauthorizationRequired do
      access_token(http:).call
    end

    assert_equal "GitHub reauthorization is required", error.message
    assert_equal "old-access-token", @connection.reload.access_token
    assert_equal "old-refresh-token", @connection.refresh_token
  end

  test "keeps temporary GitHub failures retryable without replacing credentials" do
    http = FakeHttp.new(response: json_response({ message: "temporarily unavailable" }, code: "503"))

    error = assert_raises Github::AccessToken::Error do
      access_token(http:).call
    end

    assert_equal "GitHub credentials could not be refreshed", error.message
    assert_equal "old-access-token", @connection.reload.access_token
    assert_equal "old-refresh-token", @connection.refresh_token
  end

  private
    def access_token(http:)
      Github::AccessToken.new(
        connection: @connection,
        now: NOW,
        http:,
        client_id: "test-client-id",
        client_secret: "test-client-secret"
      )
    end

    def success_response
      json_response({
        access_token: "new-access-token",
        expires_in: 8.hours.to_i,
        refresh_token: "new-refresh-token",
        refresh_token_expires_in: 15_897_600,
        token_type: "bearer",
        scope: ""
      })
    end

    def json_response(body, code: "200")
      response_class = code == "200" ? Net::HTTPOK : Net::HTTPServiceUnavailable
      response = response_class.new("1.1", code, "Response")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate(body)
      response
    end

    def request_parameters(http)
      URI.decode_www_form(http.request.body).to_h
    end

    def raw_database_value(column)
      GithubConnection.connection.select_value(<<~SQL.squish)
        SELECT #{column}
        FROM github_connections
        WHERE id = #{@connection.id}
      SQL
    end
end
