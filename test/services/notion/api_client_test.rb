require "test_helper"

class Notion::ApiClientTest < ActiveSupport::TestCase
  DATA_SOURCE_ID = "00000000-0000-8000-8000-000000000001"

  class FakeHttp
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def start(*)
      response = @responses.shift
      requests = @requests
      client = Object.new
      client.define_singleton_method(:request) do |request|
        requests << request
        response
      end
      yield(client)
    end
  end

  test "paginates authorized data sources with bearer authentication" do
    http = FakeHttp.new(
      json_response(list_response([ { object: "data_source", id: DATA_SOURCE_ID } ], has_more: true, next_cursor: "cursor")),
      json_response(list_response([]))
    )

    sources = client(http:).data_sources

    assert_equal [ DATA_SOURCE_ID ], sources.map { |source| source.fetch("id") }
    assert_equal 2, http.requests.length
    assert_equal "Bearer access-token", http.requests.first["Authorization"]
    assert_equal "2026-03-11", http.requests.first["Notion-Version"]
    assert_equal "cursor", JSON.parse(http.requests.second.body).fetch("start_cursor")
  end

  test "queries only selected properties and paginates every application" do
    http = FakeHttp.new(
      json_response(list_response([ { object: "page", id: "page-1" } ], has_more: true, next_cursor: "cursor")),
      json_response(list_response([ { object: "page", id: "page-2" } ]))
    )

    pages = client(http:).applications(
      data_source_id: DATA_SOURCE_ID,
      property_ids: [ "title", "date-id" ]
    )

    assert_equal %w[page-1 page-2], pages.map { |page| page.fetch("id") }
    query = URI.decode_www_form(http.requests.first.uri.query).group_by(&:first)
    assert_equal [ "title", "date-id" ], query.fetch("filter_properties[]").map(&:last)
    assert_equal "cursor", JSON.parse(http.requests.second.body).fetch("start_cursor")
  end

  test "distinguishes unauthorized and inaccessible responses" do
    unauthorized = FakeHttp.new(json_response({}, code: "401"))
    inaccessible = FakeHttp.new(json_response({}, code: "404"))

    assert_raises Notion::ApiClient::Unauthorized do
      client(http: unauthorized).data_sources
    end
    assert_raises Notion::ApiClient::AccessDenied do
      client(http: inaccessible).data_source(DATA_SOURCE_ID)
    end
  end

  private
    def client(http:)
      Notion::ApiClient.new(access_token: "access-token", http:)
    end

    def list_response(results, has_more: false, next_cursor: nil)
      {
        object: "list",
        results:,
        has_more:,
        next_cursor:,
        request_status: { type: "complete" }
      }
    end

    def json_response(body, code: "200")
      response_class = case code
      when "200" then Net::HTTPOK
      when "401" then Net::HTTPUnauthorized
      else Net::HTTPNotFound
      end
      response = response_class.new("1.1", code, "Response")
      response.instance_variable_set(:@read, true)
      response.body = JSON.generate(body)
      response
    end
end
