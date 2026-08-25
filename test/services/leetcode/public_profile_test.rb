require "test_helper"

class Leetcode::PublicProfileTest < ActiveSupport::TestCase
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

  test "requests only the public ownership fields" do
    http = FakeHttp.new(http_response(success_payload))
    profile = Leetcode::PublicProfile.new(username: "exampleuser", http:).call
    request_payload = JSON.parse(http.request.body)

    assert_equal "exampleuser", profile.username
    assert_equal "hello grindfolio-verify-token", profile.about_me
    assert_equal({ "username" => "exampleuser" }, request_payload.fetch("variables"))
    assert_includes request_payload.fetch("query"), "aboutMe"
    assert_not_includes request_payload.fetch("query"), "userCalendar"
    assert_equal "Grindfolio LeetCode unsupported beta", http.request["User-Agent"]
    assert_nil http.request["Authorization"]
    assert_nil http.request["Cookie"]
  end

  test "distinguishes a missing public user" do
    http = FakeHttp.new(
      http_response(
        data: { matchedUser: nil },
        errors: [ { message: "That user does not exist." } ]
      )
    )

    assert_raises Leetcode::PublicProfile::UserNotFound do
      Leetcode::PublicProfile.new(username: "missing-user", http:).call
    end
  end

  test "hard stops on provider access controls" do
    [ Net::HTTPForbidden, Net::HTTPTooManyRequests ].each do |response_class|
      response = response_class.new("1.1", response_class == Net::HTTPForbidden ? "403" : "429", "Blocked")
      response.instance_variable_set(:@read, true)
      response.body = "blocked"

      assert_raises Leetcode::PublicProfile::AccessBlocked do
        Leetcode::PublicProfile.new(username: "exampleuser", http: FakeHttp.new(response)).call
      end
    end
  end

  test "treats a non-JSON success response as an access block" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = "<html>Complete this challenge</html>"

    assert_raises Leetcode::PublicProfile::AccessBlocked do
      Leetcode::PublicProfile.new(username: "exampleuser", http: FakeHttp.new(response)).call
    end
  end

  test "rejects other provider and response-shape failures without partial data" do
    unavailable = Net::HTTPServiceUnavailable.new("1.1", "503", "Unavailable")
    unavailable.instance_variable_set(:@read, true)
    unavailable.body = "unavailable"

    assert_raises Leetcode::PublicProfile::Unavailable do
      Leetcode::PublicProfile.new(username: "exampleuser", http: FakeHttp.new(unavailable)).call
    end

    assert_raises Leetcode::PublicProfile::Unavailable do
      Leetcode::PublicProfile.new(
        username: "exampleuser",
        http: FakeHttp.new(http_response(data: { matchedUser: {} }))
      ).call
    end
  end

  private
    def http_response(body)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate(body)
      response
    end

    def success_payload
      {
        data: {
          matchedUser: {
            username: "exampleuser",
            profile: {
              aboutMe: "hello grindfolio-verify-token"
            }
          }
        }
      }
    end
end
