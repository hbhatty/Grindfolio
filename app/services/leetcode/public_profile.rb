require "json"
require "net/http"

module Leetcode
  class PublicProfile
    class Error < StandardError; end
    class AccessBlocked < Error; end
    class Unavailable < Error; end
    class UserNotFound < Error; end

    Result = Data.define(:username, :about_me)

    ENDPOINT = URI("https://leetcode.com/graphql/").freeze
    QUERY = <<~GRAPHQL.freeze
      query GrindfolioLeetCodeOwnership($username: String!) {
        matchedUser(username: $username) {
          username
          profile {
            aboutMe
          }
        }
      }
    GRAPHQL

    def initialize(username:, http: Net::HTTP)
      @username = username
      @http = http
    end

    def call
      response = perform_request
      raise AccessBlocked, "LeetCode access controls blocked the request" if [ 403, 429 ].include?(response.code.to_i)
      raise Unavailable, "LeetCode returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      raise_graphql_error(payload) if payload["errors"].present?

      matched_user = payload.dig("data", "matchedUser")
      raise UserNotFound, "LeetCode user was not found" unless matched_user

      Result.new(
        username: matched_user.fetch("username"),
        about_me: matched_user.dig("profile", "aboutMe").to_s
      )
    rescue JSON::ParserError => error
      raise AccessBlocked, "LeetCode returned a non-JSON response", cause: error
    rescue KeyError, TypeError => error
      raise Unavailable, "LeetCode returned an unexpected response", cause: error
    end

    private
      attr_reader :username, :http

      def perform_request
        request = Net::HTTP::Post.new(ENDPOINT)
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Grindfolio LeetCode unsupported beta"
        request.body = JSON.generate(
          query: QUERY,
          variables: { username: }
        )

        http.start(
          ENDPOINT.host,
          ENDPOINT.port,
          use_ssl: true,
          open_timeout: 5,
          read_timeout: 15
        ) { |client| client.request(request) }
      rescue Timeout::Error, SocketError, SystemCallError => error
        raise Unavailable, "LeetCode could not be reached", cause: error
      end

      def raise_graphql_error(payload)
        messages = payload.fetch("errors").filter_map { |error| error["message"] }
        if messages.any? { |message| message.match?(/does not exist/i) }
          raise UserNotFound, "LeetCode user was not found"
        end

        raise Unavailable, "LeetCode rejected the profile query"
      end
  end
end
