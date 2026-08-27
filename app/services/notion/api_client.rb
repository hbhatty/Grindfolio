require "net/http"
require "uri"

module Notion
  class ApiClient
    API_ORIGIN = "https://api.notion.com"
    NOTION_VERSION = "2026-03-11"

    class Error < StandardError; end
    class Unauthorized < Error; end
    class AccessDenied < Error; end

    def initialize(access_token:, http: Net::HTTP)
      @access_token = access_token
      @http = http
    end

    def data_sources
      paginate("/v1/search", method: :post) do |cursor|
        body = {
          page_size: 100,
          filter: { property: "object", value: "data_source" }
        }
        body[:start_cursor] = cursor if cursor
        body
      end
    end

    def data_source(data_source_id)
      get("/v1/data_sources/#{validated_id(data_source_id)}")
    end

    def applications(data_source_id:, property_ids:)
      query = URI.encode_www_form(property_ids.map { |id| [ "filter_properties[]", id ] })
      paginate("/v1/data_sources/#{validated_id(data_source_id)}/query?#{query}", method: :post) do |cursor|
        body = { page_size: 100 }
        body[:start_cursor] = cursor if cursor
        body
      end
    end

    private
      attr_reader :access_token, :http

      def paginate(path, method:)
        results = []
        cursor = nil

        loop do
          payload = if method == :post
            post(path, yield(cursor))
          else
            get(path)
          end
          validate_list!(payload)
          results.concat(payload.fetch("results"))
          break unless payload["has_more"]

          cursor = payload["next_cursor"]
          raise Error, "Notion omitted a pagination cursor" if cursor.blank?
        end

        results
      rescue KeyError, TypeError
        raise Error, "Notion returned an invalid paginated response"
      end

      def get(path)
        request(Net::HTTP::Get.new(uri(path)))
      end

      def post(path, body)
        http_request = Net::HTTP::Post.new(uri(path))
        http_request["Content-Type"] = "application/json"
        http_request.body = JSON.generate(body)
        request(http_request)
      end

      def request(http_request)
        raise Unauthorized, "Notion credentials are missing" if access_token.blank?

        http_request["Authorization"] = "Bearer #{access_token}"
        http_request["Accept"] = "application/json"
        http_request["Notion-Version"] = NOTION_VERSION

        response = http.start(
          http_request.uri.host,
          http_request.uri.port,
          use_ssl: true,
          open_timeout: 10,
          read_timeout: 30
        ) { |connection| connection.request(http_request) }

        case response.code.to_i
        when 200..299
          JSON.parse(response.body)
        when 401
          raise Unauthorized, "Notion rejected the current access token"
        when 403, 404
          raise AccessDenied, "Notion did not grant access to the requested resource"
        else
          raise Error, "Notion request failed without retry"
        end
      rescue JSON::ParserError
        raise Error, "Notion returned a non-JSON response"
      rescue Timeout::Error, SocketError, SystemCallError => error
        raise Error, "Notion could not be reached", cause: error
      end

      def uri(path)
        URI.join(API_ORIGIN, path)
      end

      def validate_list!(payload)
        raise TypeError unless payload["object"] == "list"
        raise Error, "Notion returned an incomplete result" if payload.dig("request_status", "type") == "incomplete"
        raise TypeError unless payload["results"].is_a?(Array)
      end

      def validated_id(value)
        id = value.to_s
        return id if id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)

        raise AccessDenied, "Notion resource ID is invalid"
      end
  end
end
