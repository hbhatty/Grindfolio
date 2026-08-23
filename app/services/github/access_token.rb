require "json"
require "net/http"

module Github
  class AccessToken
    class Error < StandardError; end
    class ReauthorizationRequired < Error; end

    ENDPOINT = URI("https://github.com/login/oauth/access_token").freeze
    REFRESH_MARGIN = 5.minutes
    REAUTHORIZATION_ERRORS = %w[bad_refresh_token].freeze

    def initialize(
      connection:,
      now: Time.current,
      http: Net::HTTP,
      client_id: Rails.application.credentials.dig(:github_app, :client_id),
      client_secret: Rails.application.credentials.dig(:github_app, :client_secret)
    )
      @connection = connection
      @now = now
      @http = http
      @client_id = client_id
      @client_secret = client_secret
    end

    def call
      connection.with_lock do
        return connection.access_token if access_token_usable?

        raise ReauthorizationRequired, "GitHub reauthorization is required" if refresh_token_expired?

        refresh_credentials!
      end
    rescue ReauthorizationRequired
      raise
    rescue ActiveRecord::ActiveRecordError,
      ActiveRecord::Encryption::Errors::Decryption,
      JSON::ParserError,
      KeyError,
      ArgumentError,
      TypeError => error
      raise Error, "GitHub credentials could not be refreshed", cause: error
    end

    private
      attr_reader :connection, :now, :http, :client_id, :client_secret

      def access_token_usable?
        connection.access_token_expires_at > now + REFRESH_MARGIN
      end

      def refresh_token_expired?
        connection.refresh_token_expires_at&.<= now
      end

      def refresh_credentials!
        validate_client_credentials!
        response = perform_request
        payload = JSON.parse(response.body)
        handle_provider_error!(payload)
        raise Error, "GitHub credentials could not be refreshed" unless response.is_a?(Net::HTTPSuccess)

        persist_credentials!(payload)
      end

      def validate_client_credentials!
        return if client_id.present? && client_secret.present?

        raise Error, "GitHub credentials could not be refreshed"
      end

      def perform_request
        request = Net::HTTP::Post.new(ENDPOINT)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request["User-Agent"] = "Gridfolio"
        request.set_form_data(
          client_id:,
          client_secret:,
          grant_type: "refresh_token",
          refresh_token: connection.refresh_token
        )

        http.start(
          ENDPOINT.host,
          ENDPOINT.port,
          use_ssl: true,
          open_timeout: 5,
          read_timeout: 15
        ) { |client| client.request(request) }
      rescue Timeout::Error, SocketError, SystemCallError => error
        raise Error, "GitHub could not be reached to refresh credentials", cause: error
      end

      def handle_provider_error!(payload)
        error_code = payload["error"].to_s
        return if error_code.blank?

        if REAUTHORIZATION_ERRORS.include?(error_code)
          raise ReauthorizationRequired, "GitHub reauthorization is required"
        end

        raise Error, "GitHub credentials could not be refreshed"
      end

      def persist_credentials!(payload)
        access_token = payload.fetch("access_token").to_s.presence
        refresh_token = payload.fetch("refresh_token").to_s.presence
        access_lifetime = positive_seconds(payload.fetch("expires_in"))
        refresh_lifetime = positive_seconds(payload.fetch("refresh_token_expires_in"))
        raise KeyError if access_token.blank? || refresh_token.blank?

        connection.update_columns(
          access_token:,
          refresh_token:,
          access_token_expires_at: now + access_lifetime.seconds,
          refresh_token_expires_at: now + refresh_lifetime.seconds,
          updated_at: now
        )
        access_token
      end

      def positive_seconds(value)
        seconds = Integer(value)
        raise ArgumentError unless seconds.positive?

        seconds
      end
  end
end
