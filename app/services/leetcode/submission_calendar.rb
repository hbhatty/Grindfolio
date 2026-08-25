require "json"
require "net/http"
require "openssl"

module Leetcode
  class SubmissionCalendar
    class Error < StandardError; end
    class AccessBlocked < Error; end
    class GraphqlError < Error; end
    class InvalidCalendar < Error; end
    class InvalidResponse < Error; end
    class Unavailable < Error; end
    class UserNotFound < Error; end

    Day = Data.define(:activity_date, :submission_count)
    Result = Data.define(:username, :days)

    ENDPOINT = URI("https://leetcode.com/graphql/").freeze
    QUERY = <<~GRAPHQL.freeze
      query GrindfolioLeetCodeCalendar($username: String!, $year: Int) {
        matchedUser(username: $username) {
          username
          userCalendar(year: $year) {
            submissionCalendar
          }
        }
      }
    GRAPHQL

    def initialize(username:, year:, http: Net::HTTP)
      @username = username
      @year = Integer(year)
      @http = http
    end

    def call
      response = perform_request
      if [ 403, 429 ].include?(response.code.to_i)
        raise AccessBlocked, "LeetCode access controls blocked the calendar request"
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise Unavailable, "LeetCode calendar is unavailable"
      end

      payload = parse_payload(response.body)
      raise GraphqlError, "LeetCode rejected the calendar query" if graphql_errors?(payload)

      build_result(payload)
    end

    private
      attr_reader :username, :year, :http

      def perform_request
        request = Net::HTTP::Post.new(ENDPOINT)
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Grindfolio LeetCode unsupported beta"
        request.body = JSON.generate(
          query: QUERY,
          variables: { username:, year: }
        )

        http.start(
          ENDPOINT.host,
          ENDPOINT.port,
          use_ssl: true,
          open_timeout: 5,
          read_timeout: 15
        ) { |client| client.request(request) }
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
        raise Unavailable, "LeetCode calendar could not be reached", cause: error
      end

      def parse_payload(body)
        payload = JSON.parse(body)
        return payload if payload.is_a?(Hash)

        raise InvalidResponse, "LeetCode returned an unexpected calendar response"
      rescue JSON::ParserError => error
        raise InvalidResponse, "LeetCode returned an unexpected calendar response", cause: error
      end

      def graphql_errors?(payload)
        errors = payload["errors"]
        errors.present?
      end

      def build_result(payload)
        matched_user = payload.fetch("data").fetch("matchedUser")
        raise UserNotFound, "LeetCode user was not found" unless matched_user

        canonical_username = matched_user.fetch("username")
        unless canonical_username.is_a?(String) && canonical_username.present?
          raise UserNotFound, "LeetCode user was not found"
        end

        encoded_calendar = matched_user.fetch("userCalendar").fetch("submissionCalendar")
        Result.new(username: canonical_username, days: parse_calendar(encoded_calendar))
      rescue KeyError, TypeError, NoMethodError => error
        raise InvalidResponse, "LeetCode returned an unexpected calendar response", cause: error
      end

      def parse_calendar(encoded_calendar)
        calendar = JSON.parse(encoded_calendar)
        unless calendar.is_a?(Hash)
          raise InvalidCalendar, "LeetCode returned an invalid submission calendar"
        end

        calendar.map do |timestamp, count|
          Day.new(
            activity_date: parse_date(timestamp),
            submission_count: parse_count(count)
          )
        end
      rescue JSON::ParserError, TypeError => error
        raise InvalidCalendar, "LeetCode returned an invalid submission calendar", cause: error
      end

      def parse_date(timestamp)
        unless timestamp.is_a?(String) && timestamp.match?(/\A(?:0|[1-9]\d*)\z/)
          raise InvalidCalendar, "LeetCode returned an invalid submission calendar"
        end

        time = Time.at(Integer(timestamp, 10)).utc
        unless time.hour.zero? && time.min.zero? && time.sec.zero? && time.year == year
          raise InvalidCalendar, "LeetCode returned an invalid submission calendar"
        end

        time.to_date
      rescue ArgumentError, RangeError => error
        raise InvalidCalendar, "LeetCode returned an invalid submission calendar", cause: error
      end

      def parse_count(count)
        unless count.is_a?(Integer) && count >= 0
          raise InvalidCalendar, "LeetCode returned an invalid submission calendar"
        end

        count
      end
  end
end
