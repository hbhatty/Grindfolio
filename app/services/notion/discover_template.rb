module Notion
  class DiscoverTemplate
    EXPECTED_PROPERTIES = {
      company_name: [ "Company Name", "title" ],
      application_date: [ "Application Date", "date" ],
      role: [ "Role / Position", "rich_text" ],
      status: [ "Application Status", "status" ]
    }.freeze

    Template = Data.define(:data_source_id, :property_ids)

    class Error < StandardError; end

    def self.call(client:)
      new(client:).call
    end

    def initialize(client:)
      @client = client
    end

    def call
      source_ids = client.data_sources.filter_map do |source|
        source["id"] if source["object"] == "data_source"
      end.uniq
      raise Error, "Authorize exactly one Notion data source" unless source_ids.one?

      source = client.data_source(source_ids.first)
      raise Error, "Notion returned an unexpected data source" unless source["object"] == "data_source"
      raise Error, "Notion data source changed during discovery" unless source["id"] == source_ids.first

      properties = source.fetch("properties")
      property_ids = EXPECTED_PROPERTIES.to_h do |key, (name, type)|
        property = properties.fetch(name)
        unless property["type"] == type && property["id"].is_a?(String) && property["id"].present?
          raise Error, "Notion tracker does not match the supported template"
        end

        [ key, property.fetch("id") ]
      end

      Template.new(data_source_id: source_ids.first, property_ids:)
    rescue KeyError, TypeError
      raise Error, "Notion tracker does not match the supported template"
    end

    private
      attr_reader :client
  end
end
