require "net/http"
require "uri"

module Notion
  class RefreshAccessToken
    ENDPOINT = URI("https://api.notion.com/v1/oauth/token")
    NOTION_VERSION = "2026-03-11"

    class Error < StandardError; end
    class ReauthorizationRequired < Error; end

    def self.call(connection:)
      new(connection:).call
    end

    def initialize(
      connection:,
      client_id: Rails.application.config.x.notion.client_id,
      client_secret: Rails.application.config.x.notion.client_secret,
      http: Net::HTTP
    )
      @connection = connection
      @client_id = client_id
      @client_secret = client_secret
      @http = http
    end

    def call
      connection.with_lock do
        validate_inputs!
        response = perform_request
        if [ 400, 401 ].include?(response.code.to_i)
          raise ReauthorizationRequired, "Notion refresh credentials were rejected"
        end
        raise Error, "Notion credentials could not be refreshed" unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)
        access_token = required_string(payload, "access_token")
        refresh_token = required_string(payload, "refresh_token")
        connection.update!(access_token:, refresh_token:)
        access_token
      end
    rescue JSON::ParserError, KeyError, TypeError, ActiveRecord::RecordInvalid
      raise Error, "Notion returned invalid refreshed credentials"
    rescue Timeout::Error, SocketError, SystemCallError => error
      raise Error, "Notion could not be reached to refresh credentials", cause: error
    end

    private
      attr_reader :connection, :client_id, :client_secret, :http

      def validate_inputs!
        return if connection.refresh_token.present? && client_id.present? && client_secret.present?

        raise ReauthorizationRequired, "Notion refresh credentials are missing"
      end

      def perform_request
        request = Net::HTTP::Post.new(ENDPOINT)
        request.basic_auth(client_id, client_secret)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/json"
        request["Notion-Version"] = NOTION_VERSION
        request.body = JSON.generate(
          grant_type: "refresh_token",
          refresh_token: connection.refresh_token
        )

        http.start(
          ENDPOINT.host,
          ENDPOINT.port,
          use_ssl: true,
          open_timeout: 10,
          read_timeout: 20
        ) { |client| client.request(request) }
      end

      def required_string(payload, key)
        value = payload.fetch(key)
        raise TypeError unless value.is_a?(String) && value.present?

        value
      end
  end
end
