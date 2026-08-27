require "test_helper"

class Notion::SyncApplicationsTest < ActiveSupport::TestCase
  DATA_SOURCE_ID = "4545a665-49e3-825d-8b36-87141868ab3d"
  NOW = Time.utc(2026, 8, 26, 20)

  class FakeClient
    def initialize(pages: [], schema: nil, error: nil)
      @pages = pages
      @schema = schema
      @error = error
    end

    def data_sources
      raise @error if @error

      [ { "object" => "data_source", "id" => DATA_SOURCE_ID } ]
    end

    def data_source(*)
      @schema
    end

    def applications(**)
      @pages
    end
  end

  setup do
    @connection = User.create!(time_zone: "America/Toronto").create_notion_connection!(
      workspace_id: "workspace-id",
      workspace_name: "Example workspace",
      bot_id: "bot-id",
      owner_user_id: "owner-user-id",
      access_token: "access-token",
      refresh_token: "refresh-token",
      tracking_started_on: Date.new(2026, 8, 26),
      authorized_at: Time.utc(2026, 8, 26, 16)
    )
  end

  test "caches only complete tracked applications after validating the exact template" do
    pages = [
      page(id: "current", date: "2026-08-26"),
      page(id: "historical", date: "2026-08-25"),
      page(id: "missing-date", date: nil),
      page(id: "future", date: "2026-08-27")
    ]

    count = synchronize(pages:)

    assert_equal 1, count
    assert_equal [ "current" ], @connection.applications.pluck(:provider_page_id)
    application = @connection.applications.first
    assert_equal Date.new(2026, 8, 26), application.applied_on
    assert_equal "Example Company", application.company_name
    assert_equal "Software Engineering Intern", application.role
    assert_equal "Applied", application.current_status
    assert_equal NOW, @connection.reload.last_synced_at
    assert_nil @connection.last_sync_error
  end

  test "authoritatively updates corrected rows and removes absent rows" do
    current = @connection.applications.create!(application_attributes(provider_page_id: "current"))
    created_at = current.created_at
    @connection.applications.create!(application_attributes(provider_page_id: "deleted"))

    synchronize(
      pages: [
        page(
          id: "current",
          date: "2026-08-26",
          company: "Renamed Company",
          role: "Updated Role",
          status: "Interview Scheduled"
        )
      ]
    )

    assert_equal [ "current" ], @connection.applications.pluck(:provider_page_id)
    current.reload
    assert_equal "Renamed Company", current.company_name
    assert_equal "Updated Role", current.role
    assert_equal "Interview Scheduled", current.current_status
    assert_equal created_at, current.created_at
  end

  test "preserves the prior cache and successful timestamp on provider failure" do
    cached = @connection.applications.create!(application_attributes)
    previous_sync = Time.utc(2026, 8, 26, 19)
    @connection.update!(last_synced_at: previous_sync)
    client = FakeClient.new(schema:, error: Notion::ApiClient::Error.new("secret provider failure"))

    error = assert_raises Notion::SyncApplications::Error do
      service(api_client_factory: ->(_token) { client }).call
    end

    assert_equal Notion::SyncApplications::PROVIDER_ERROR, error.message
    assert_equal [ cached.id ], @connection.applications.pluck(:id)
    assert_equal previous_sync, @connection.reload.last_synced_at
    assert_equal Notion::SyncApplications::PROVIDER_ERROR, @connection.last_sync_error
    assert_not_includes @connection.last_sync_error, "secret provider failure"
  end

  test "refreshes rejected access credentials once before retrying" do
    clients = [
      FakeClient.new(error: Notion::ApiClient::Unauthorized.new("expired")),
      FakeClient.new(schema:, pages: [ page(id: "current", date: "2026-08-26") ])
    ]
    factory = ->(_token) { clients.shift }
    refresher = lambda do |connection:|
      connection.update!(access_token: "refreshed-access", refresh_token: "refreshed-refresh")
      "refreshed-access"
    end

    count = service(api_client_factory: factory, credential_refresher: refresher).call

    assert_equal 1, count
    assert_equal "refreshed-access", @connection.reload.access_token
    assert_empty clients
  end

  private
    def synchronize(pages:)
      service(api_client_factory: ->(_token) { FakeClient.new(schema:, pages:) }).call
    end

    def service(
      api_client_factory:,
      credential_refresher: Notion::RefreshAccessToken
    )
      Notion::SyncApplications.new(
        connection: @connection,
        now: NOW,
        api_client_factory:,
        credential_refresher:
      )
    end

    def schema
      {
        "object" => "data_source",
        "id" => DATA_SOURCE_ID,
        "properties" => {
          "Company Name" => { "id" => "title", "type" => "title" },
          "Application Date" => { "id" => "date-id", "type" => "date" },
          "Role / Position" => { "id" => "role-id", "type" => "rich_text" },
          "Application Status" => { "id" => "status-id", "type" => "status" }
        }
      }
    end

    def page(
      id:,
      date:,
      company: "Example Company",
      role: "Software Engineering Intern",
      status: "Applied"
    )
      {
        "object" => "page",
        "id" => id,
        "last_edited_time" => "2026-08-26T19:00:00Z",
        "properties" => {
          "Company Name" => {
            "id" => "title",
            "type" => "title",
            "title" => [ { "plain_text" => company } ]
          },
          "Application Date" => {
            "id" => "date-id",
            "type" => "date",
            "date" => date ? { "start" => date, "end" => nil, "time_zone" => nil } : nil
          },
          "Role / Position" => {
            "id" => "role-id",
            "type" => "rich_text",
            "rich_text" => [ { "plain_text" => role } ]
          },
          "Application Status" => {
            "id" => "status-id",
            "type" => "status",
            "status" => { "name" => status }
          }
        }
      }
    end

    def application_attributes(provider_page_id: "cached")
      {
        provider_page_id:,
        applied_on: Date.new(2026, 8, 26),
        company_name: "Cached Company",
        role: "Cached Role",
        current_status: "Applied",
        provider_last_edited_at: Time.utc(2026, 8, 26, 18)
      }
    end
end
