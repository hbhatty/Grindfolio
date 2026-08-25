require "test_helper"

class Github::ContributionCalendarTest < ActiveSupport::TestCase
  FROM_DATE = Date.new(2026, 8, 21)
  TO_DATE = Date.new(2026, 8, 22)

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

  test "requests and returns a typed contribution calendar" do
    http = FakeHttp.new(http_response(success_payload))
    calendar = Github::ContributionCalendar.new(
      access_token: "secret-token",
      from_date: FROM_DATE,
      to_date: TO_DATE,
      http:
    )

    result = calendar.call
    request_payload = JSON.parse(http.request.body)

    assert_equal "octocat", result[:github_login]
    assert_equal 42, result[:github_database_id]
    assert_equal "MDQ6VXNlcjQy", result[:github_node_id]
    assert_equal 3, result[:total_contributions]
    assert_equal 1, result[:restricted_contributions]
    assert_equal [
      {
        activity_date: FROM_DATE,
        contribution_count: 1,
        contribution_level: "FIRST_QUARTILE"
      },
      {
        activity_date: TO_DATE,
        contribution_count: 2,
        contribution_level: "SECOND_QUARTILE"
      }
    ], result[:days]
    assert_equal "2026-08-21T00:00:00Z", request_payload.dig("variables", "from")
    assert_equal "2026-08-22T23:59:59Z", request_payload.dig("variables", "to")
    assert_equal "Grindfolio", http.request["User-Agent"]
    assert_not_includes result.inspect, "secret-token"
  end

  test "rejects GraphQL errors without returning partial data" do
    calendar = Github::ContributionCalendar.new(
      access_token: "secret-token",
      from_date: FROM_DATE,
      to_date: TO_DATE,
      http: FakeHttp.new(http_response(errors: [ { message: "Resource not accessible" } ]))
    )

    error = assert_raises(Github::ContributionCalendar::Error) { calendar.call }

    assert_equal "Resource not accessible", error.message
  end

  test "rejects an invalid requested date range before making a request" do
    error = assert_raises ArgumentError do
      Github::ContributionCalendar.new(
        access_token: "secret-token",
        from_date: TO_DATE,
        to_date: FROM_DATE
      )
    end

    assert_equal "GitHub calendar start must not follow its end", error.message
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
          viewer: {
            id: "MDQ6VXNlcjQy",
            databaseId: 42,
            login: "octocat",
            contributionsCollection: {
              startedAt: "2026-08-21T00:00:00Z",
              endedAt: "2026-08-22T23:59:59Z",
              restrictedContributionsCount: 1,
              contributionCalendar: {
                totalContributions: 3,
                weeks: [
                  {
                    contributionDays: [
                      {
                        date: "2026-08-21",
                        contributionCount: 1,
                        contributionLevel: "FIRST_QUARTILE"
                      },
                      {
                        date: "2026-08-22",
                        contributionCount: 2,
                        contributionLevel: "SECOND_QUARTILE"
                      }
                    ]
                  }
                ]
              }
            }
          },
          rateLimit: {
            cost: 1,
            remaining: 4_999,
            resetAt: "2026-08-22T13:00:00Z"
          }
        }
      }
    end
end
