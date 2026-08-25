require "json"
require "net/http"

module Github
  class ContributionCalendar
    class Error < StandardError; end

    ENDPOINT = URI("https://api.github.com/graphql").freeze
    QUERY = <<~GRAPHQL.freeze
      query GrindfolioContributionCalendar($from: DateTime!, $to: DateTime!) {
        viewer {
          id
          databaseId
          login
          contributionsCollection(from: $from, to: $to) {
            startedAt
            endedAt
            restrictedContributionsCount
            contributionCalendar {
              totalContributions
              weeks {
                contributionDays {
                  date
                  contributionCount
                  contributionLevel
                }
              }
            }
          }
        }
        rateLimit {
          cost
          remaining
          resetAt
        }
      }
    GRAPHQL

    def initialize(access_token:, from_date:, to_date:, http: Net::HTTP)
      @access_token = access_token
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @http = http

      raise ArgumentError, "GitHub calendar start must not follow its end" if @from_date > @to_date
    end

    def call
      response = perform_request
      raise Error, "GitHub returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      raise Error, graphql_error_message(payload) if payload["errors"].present?

      build_result(payload.fetch("data"))
    rescue JSON::ParserError, KeyError, Date::Error, TypeError => error
      raise Error, "GitHub returned an unexpected response", cause: error
    end

    private
      attr_reader :access_token, :from_date, :to_date, :http

      def perform_request
        request = Net::HTTP::Post.new(ENDPOINT)
        request["Accept"] = "application/vnd.github+json"
        request["Authorization"] = "Bearer #{access_token}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Grindfolio"
        request.body = JSON.generate(
          query: QUERY,
          variables: {
            from: "#{from_date.iso8601}T00:00:00Z",
            to: "#{to_date.iso8601}T23:59:59Z"
          }
        )

        http.start(
          ENDPOINT.host,
          ENDPOINT.port,
          use_ssl: true,
          open_timeout: 5,
          read_timeout: 15
        ) { |client| client.request(request) }
      rescue Timeout::Error, SocketError, SystemCallError => error
        raise Error, "GitHub could not be reached", cause: error
      end

      def graphql_error_message(payload)
        messages = payload.fetch("errors").filter_map { |error| error["message"] }
        messages.any? ? messages.join("; ") : "GitHub rejected the GraphQL query"
      end

      def build_result(data)
        viewer = data.fetch("viewer")
        collection = viewer.fetch("contributionsCollection")
        calendar = collection.fetch("contributionCalendar")
        days = calendar.fetch("weeks").flat_map { |week| week.fetch("contributionDays") }

        {
          github_login: viewer.fetch("login"),
          github_database_id: viewer.fetch("databaseId"),
          github_node_id: viewer.fetch("id"),
          started_at: collection.fetch("startedAt"),
          ended_at: collection.fetch("endedAt"),
          total_contributions: calendar.fetch("totalContributions"),
          restricted_contributions: collection.fetch("restrictedContributionsCount"),
          days: days.map { |day| build_day(day) },
          rate_limit: data.fetch("rateLimit")
        }
      end

      def build_day(day)
        {
          activity_date: Date.iso8601(day.fetch("date")),
          contribution_count: Integer(day.fetch("contributionCount")),
          contribution_level: day.fetch("contributionLevel")
        }
      end
  end
end
