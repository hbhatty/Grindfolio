require "net/http"
require "uri"

module Notion
  class ExchangeAuthorizationCode
    ENDPOINT = URI("https://api.notion.com/v1/oauth/token")
    NOTION_VERSION = "2026-03-11"

    class Error < StandardError; end

    def self.call(code:, redirect_uri:)
      new(code:, redirect_uri:).call
    end

    def initialize(
      code:,
      redirect_uri:,
      client_id: Rails.application.config.x.notion.client_id,
      client_secret: Rails.application.config.x.notion.client_secret,
      http: Net::HTTP
    )
      @code = code
      @redirect_uri = redirect_uri
      @client_id = client_id
      @client_secret = client_secret
      @http = http
    end

    def call
      validate_inputs!
      response = perform_request
      raise Error, "Notion authorization could not be completed" unless response.is_a?(Net::HTTPSuccess)

      normalize(JSON.parse(response.body))
    rescue JSON::ParserError, KeyError, TypeError
      raise Error, "Notion returned an invalid authorization response"
    rescue Timeout::Error, SocketError, SystemCallError => error
      raise Error, "Notion could not be reached during authorization", cause: error
    end

    private
      attr_reader :code, :redirect_uri, :client_id, :client_secret, :http

      def validate_inputs!
        return if code.present? && redirect_uri.present? && client_id.present? && client_secret.present?

        raise Error, "Notion authorization is incomplete"
      end

      def perform_request
        request = Net::HTTP::Post.new(ENDPOINT)
        request.basic_auth(client_id, client_secret)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/json"
        request["Notion-Version"] = NOTION_VERSION
        request.body = JSON.generate(
          grant_type: "authorization_code",
          code:,
          redirect_uri:
        )

        http.start(
          ENDPOINT.host,
          ENDPOINT.port,
          use_ssl: true,
          open_timeout: 10,
          read_timeout: 20
        ) { |connection| connection.request(request) }
      end

      def normalize(payload)
        owner = payload.fetch("owner")
        raise TypeError unless owner.is_a?(Hash)

        {
          access_token: required_string(payload, "access_token"),
          refresh_token: required_string(payload, "refresh_token"),
          bot_id: required_string(payload, "bot_id"),
          workspace_id: required_string(payload, "workspace_id"),
          workspace_name: optional_string(payload["workspace_name"]),
          owner_user_id: owner["type"] == "user" ? optional_string(owner.dig("user", "id")) : nil
        }
      end

      def required_string(payload, key)
        value = payload.fetch(key)
        raise TypeError unless value.is_a?(String) && value.present?

        value
      end

      def optional_string(value)
        return if value.nil?
        raise TypeError unless value.is_a?(String)

        value.presence
      end
  end
end
