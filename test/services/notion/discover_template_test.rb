require "test_helper"

class Notion::DiscoverTemplateTest < ActiveSupport::TestCase
  DATA_SOURCE_ID = "4545a665-49e3-825d-8b36-87141868ab3d"

  class FakeClient
    def initialize(sources:, schema:)
      @sources = sources
      @schema = schema
    end

    def data_sources
      @sources
    end

    def data_source(*)
      @schema
    end
  end

  test "discovers duplicate-specific IDs for the exact supported template" do
    template = Notion::DiscoverTemplate.call(client: client)

    assert_equal DATA_SOURCE_ID, template.data_source_id
    assert_equal(
      {
        company_name: "title",
        application_date: "date-id",
        role: "role-id",
        status: "status-id"
      },
      template.property_ids
    )
  end

  test "requires exactly one authorized data source" do
    no_sources = client(sources: [])
    two_sources = client(
      sources: [ source_summary, source_summary.merge("id" => "5545a665-49e3-825d-8b36-87141868ab3d") ]
    )

    assert_raises Notion::DiscoverTemplate::Error do
      Notion::DiscoverTemplate.call(client: no_sources)
    end
    assert_raises Notion::DiscoverTemplate::Error do
      Notion::DiscoverTemplate.call(client: two_sources)
    end
  end

  test "rejects renamed or incompatible template properties" do
    renamed = schema
    renamed["properties"]["Applied Date"] = renamed["properties"].delete("Application Date")
    wrong_type = schema
    wrong_type["properties"]["Application Status"]["type"] = "select"

    assert_raises Notion::DiscoverTemplate::Error do
      Notion::DiscoverTemplate.call(client: client(schema: renamed))
    end
    assert_raises Notion::DiscoverTemplate::Error do
      Notion::DiscoverTemplate.call(client: client(schema: wrong_type))
    end
  end

  private
    def client(sources: [ source_summary ], schema: self.schema)
      FakeClient.new(sources:, schema:)
    end

    def source_summary
      { "object" => "data_source", "id" => DATA_SOURCE_ID }
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
      }.deep_dup
    end
end
