require "test_helper"

class Github::ContributionProbeTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 22)
  FakeHttp = Data.define(:response) do
    def start(*)
      response
    end
  end

  test "requests and returns a sanitized contribution calendar" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = JSON.generate(success_payload)
    probe = Github::ContributionProbe.new(
      access_token: "secret-token",
      today: TODAY,
      http: FakeHttp.new(response)
    )

    result = probe.call

    assert_equal "octocat", result[:github_login]
    assert_equal 42, result[:github_database_id]
    assert_equal "MDQ6VXNlcjQy", result[:github_node_id]
    assert_equal 3, result[:total_contributions]
    assert_equal 1, result[:restricted_contributions]
    assert_equal 2, result[:days].size
    assert_equal 1, result.dig(:rate_limit, "cost")
    assert_not_includes result.inspect, "secret-token"
  end

  test "rejects GraphQL errors without returning partial data" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = JSON.generate(errors: [ { message: "Resource not accessible" } ])
    probe = Github::ContributionProbe.new(
      access_token: "secret-token",
      today: TODAY,
      http: FakeHttp.new(response)
    )

    error = assert_raises(Github::ContributionProbe::Error) { probe.call }

    assert_equal "Resource not accessible", error.message
  end

  private
    def success_payload
      {
        data: {
          viewer: {
            id: "MDQ6VXNlcjQy",
            databaseId: 42,
            login: "octocat",
            contributionsCollection: {
              startedAt: "2026-07-24T00:00:00Z",
              endedAt: "2026-08-22T23:59:59Z",
              restrictedContributionsCount: 1,
              contributionCalendar: {
                totalContributions: 3,
                weeks: [
                  {
                    contributionDays: [
                      { date: "2026-08-21", contributionCount: 1 },
                      { date: "2026-08-22", contributionCount: 2 }
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
