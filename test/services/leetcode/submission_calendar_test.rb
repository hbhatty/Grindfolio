require "test_helper"

class Leetcode::SubmissionCalendarTest < ActiveSupport::TestCase
  YEAR = 2026
  USERNAME = "ExampleUser"
  ACTIVITY_DATE = Date.new(2026, 8, 7)

  class FakeHttp
    attr_reader :calls, :request, :start_arguments

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @calls = 0
    end

    def start(*arguments, **options)
      @calls += 1
      @start_arguments = [ arguments, options ]
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

  test "requests only the canonical username and submission calendar without credentials" do
    http = FakeHttp.new(response: http_response(success_payload))

    result = Leetcode::SubmissionCalendar.new(username: USERNAME, year: YEAR, http:).call
    request_payload = JSON.parse(http.request.body)

    assert_equal USERNAME, result.username
    assert_equal [
      Leetcode::SubmissionCalendar::Day.new(
        activity_date: ACTIVITY_DATE,
        submission_count: 4
      )
    ], result.days
    assert_equal({ "username" => USERNAME, "year" => YEAR }, request_payload.fetch("variables"))
    assert_equal expected_query, request_payload.fetch("query").gsub(/\s+/, " ").strip
    assert_equal "POST", http.request.method
    assert_equal "/graphql/", http.request.path
    assert_equal "application/json", http.request["Content-Type"]
    assert_equal "Grindfolio LeetCode unsupported beta", http.request["User-Agent"]
    assert_nil http.request["Authorization"]
    assert_nil http.request["Cookie"]
    assert_equal 1, http.calls
  end

  test "rejects malformed timestamps, non-midnight dates, and invalid counts" do
    invalid_calendars = [
      { "not-a-timestamp" => 1 },
      { Time.utc(YEAR, 8, 7, 0, 0, 1).to_i.to_s => 1 },
      { midnight_timestamp => -1 },
      { midnight_timestamp => 1.5 },
      { midnight_timestamp => "4" }
    ]

    invalid_calendars.each do |calendar|
      error = assert_raises Leetcode::SubmissionCalendar::InvalidCalendar do
        build_client(calendar:).call
      end

      assert_equal "LeetCode returned an invalid submission calendar", error.message
    end
  end

  test "rejects GraphQL errors without exposing provider details" do
    error = assert_raises Leetcode::SubmissionCalendar::GraphqlError do
      build_client(
        payload: {
          data: { matchedUser: nil },
          errors: [ { message: "private upstream incident 123" } ]
        }
      ).call
    end

    assert_equal "LeetCode rejected the calendar query", error.message
    assert_not_includes error.message, "private upstream incident 123"
  end

  test "distinguishes canonical user absence from an unexpected response shape" do
    missing = assert_raises Leetcode::SubmissionCalendar::UserNotFound do
      build_client(payload: { data: { matchedUser: nil } }).call
    end
    malformed = assert_raises Leetcode::SubmissionCalendar::InvalidResponse do
      build_client(payload: { data: { matchedUser: { username: USERNAME } } }).call
    end

    assert_equal "LeetCode user was not found", missing.message
    assert_equal "LeetCode returned an unexpected calendar response", malformed.message
  end

  test "rejects a non-JSON success response without exposing an access challenge or retrying" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = "<html>private access challenge token</html>"
    http = FakeHttp.new(response:)

    error = assert_raises Leetcode::SubmissionCalendar::InvalidResponse do
      Leetcode::SubmissionCalendar.new(username: USERNAME, year: YEAR, http:).call
    end

    assert_equal "LeetCode returned an unexpected calendar response", error.message
    assert_not_includes error.message, "private access challenge token"
    assert_equal 1, http.calls
  end

  test "hard stops on access controls and rejects other HTTP failures" do
    [
      [ Net::HTTPForbidden, "403" ],
      [ Net::HTTPTooManyRequests, "429" ]
    ].each do |response_class, status|
      http = FakeHttp.new(response: response(response_class, status))

      assert_raises Leetcode::SubmissionCalendar::AccessBlocked do
        Leetcode::SubmissionCalendar.new(username: USERNAME, year: YEAR, http:).call
      end
      assert_equal 1, http.calls
    end

    http = FakeHttp.new(response: response(Net::HTTPServiceUnavailable, "503"))
    error = assert_raises Leetcode::SubmissionCalendar::Unavailable do
      Leetcode::SubmissionCalendar.new(username: USERNAME, year: YEAR, http:).call
    end

    assert_equal "LeetCode calendar is unavailable", error.message
    assert_equal 1, http.calls
  end

  test "turns representative transport failures into one sanitized failure without retrying" do
    [ Timeout::Error.new("private timeout details"), SocketError.new("private DNS details") ].each do |transport_error|
      http = FakeHttp.new(error: transport_error)

      error = assert_raises Leetcode::SubmissionCalendar::Unavailable do
        Leetcode::SubmissionCalendar.new(username: USERNAME, year: YEAR, http:).call
      end

      assert_equal "LeetCode calendar could not be reached", error.message
      assert_not_includes error.message, "private"
      assert_equal 1, http.calls
    end
  end

  private
    def build_client(calendar: { midnight_timestamp => 4 }, payload: nil)
      body = payload || success_payload(calendar:)
      Leetcode::SubmissionCalendar.new(
        username: USERNAME,
        year: YEAR,
        http: FakeHttp.new(response: http_response(body))
      )
    end

    def http_response(body)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate(body)
      response
    end

    def response(response_class, status)
      value = response_class.new("1.1", status, "Provider response")
      value.instance_variable_set(:@read, true)
      value.body = "provider details"
      value
    end

    def success_payload(calendar: { midnight_timestamp => 4 })
      {
        data: {
          matchedUser: {
            username: USERNAME,
            userCalendar: {
              submissionCalendar: JSON.generate(calendar)
            }
          }
        }
      }
    end

    def midnight_timestamp
      Time.utc(YEAR, 8, 7).to_i.to_s
    end

    def expected_query
      "query GrindfolioLeetCodeCalendar($username: String!, $year: Int) { " \
        "matchedUser(username: $username) { username " \
        "userCalendar(year: $year) { submissionCalendar } } }"
    end
end
