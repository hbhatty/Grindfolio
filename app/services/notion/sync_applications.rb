require "time"

module Notion
  class SyncApplications
    PROVIDER_ERROR = "Notion activity could not be updated."
    TEMPLATE_ERROR = "The authorized Notion tracker is not supported by this proof."
    REAUTHORIZATION_ERROR = "Notion authorization needs to be renewed."

    class Error < StandardError; end
    class UnsupportedTemplate < Error; end
    class ReauthorizationRequired < Error; end

    def self.call(connection:)
      new(connection:).call
    end

    def initialize(
      connection:,
      now: Time.current,
      api_client_factory: ->(access_token) { ApiClient.new(access_token:) },
      credential_refresher: RefreshAccessToken
    )
      @connection = connection
      @now = now
      @api_client_factory = api_client_factory
      @credential_refresher = credential_refresher
    end

    def call
      applications = fetch_applications
      persist!(applications)
      applications.length
    rescue DiscoverTemplate::Error => error
      record_failure(TEMPLATE_ERROR)
      raise UnsupportedTemplate, TEMPLATE_ERROR, cause: error
    rescue RefreshAccessToken::ReauthorizationRequired, ApiClient::Unauthorized => error
      record_failure(REAUTHORIZATION_ERROR)
      raise ReauthorizationRequired, REAUTHORIZATION_ERROR, cause: error
    rescue ApiClient::Error, RefreshAccessToken::Error, ActiveRecord::ActiveRecordError,
      KeyError, TypeError, ArgumentError => error
      record_failure(PROVIDER_ERROR)
      raise Error, PROVIDER_ERROR, cause: error
    end

    private
      attr_reader :connection, :now, :api_client_factory, :credential_refresher

      def fetch_applications
        refreshed = false

        begin
          client = api_client_factory.call(connection.access_token)
          template = DiscoverTemplate.call(client:)
          pages = client.applications(
            data_source_id: template.data_source_id,
            property_ids: template.property_ids.values
          )
          parse_pages(pages, template.property_ids)
        rescue ApiClient::Unauthorized
          raise if refreshed

          credential_refresher.call(connection:)
          refreshed = true
          retry
        end
      end

      def parse_pages(pages, property_ids)
        raise TypeError unless pages.is_a?(Array)

        applications = pages.filter_map do |page|
          parse_page(page, property_ids)
        end
        page_ids = applications.map { |application| application.fetch(:provider_page_id) }
        raise TypeError unless page_ids.uniq.length == page_ids.length

        applications
      end

      def parse_page(page, property_ids)
        raise TypeError unless page["object"] == "page"
        raise TypeError unless page["properties"].is_a?(Hash)

        applied_on = application_date(page, property_ids.fetch(:application_date))
        return if applied_on.nil? || !applied_on.between?(connection.tracking_started_on, current_date)

        {
          provider_page_id: required_string(page, "id"),
          applied_on:,
          company_name: rich_text(page, property_ids.fetch(:company_name), "title", required: true),
          role: rich_text(page, property_ids.fetch(:role), "rich_text"),
          current_status: status(page, property_ids.fetch(:status)),
          provider_last_edited_at: Time.iso8601(required_string(page, "last_edited_time"))
        }
      end

      def application_date(page, property_id)
        property = page_property(page, property_id, "date")
        value = property["date"]
        return if value.nil?
        raise TypeError unless value.is_a?(Hash)

        start = value["start"]
        raise TypeError unless start.is_a?(String) && start.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        raise TypeError unless value["end"].nil?

        Date.iso8601(start)
      end

      def rich_text(page, property_id, type, required: false)
        property = page_property(page, property_id, type)
        fragments = property[type]
        raise TypeError unless fragments.is_a?(Array)

        value = fragments.filter_map { |fragment| fragment["plain_text"] }.join.presence
        raise TypeError if required && value.nil?

        value
      end

      def status(page, property_id)
        property = page_property(page, property_id, "status")
        value = property["status"]
        return if value.nil?
        raise TypeError unless value.is_a?(Hash)

        required_string(value, "name")
      end

      def page_property(page, property_id, type)
        property = page.fetch("properties").values.find { |candidate| candidate["id"] == property_id }
        raise TypeError unless property&.fetch("type", nil) == type

        property
      end

      def required_string(payload, key)
        value = payload.fetch(key)
        raise TypeError unless value.is_a?(String) && value.present?

        value
      end

      def current_date
        now.in_time_zone(connection.user.time_zone.presence || "UTC").to_date
      end

      def persist!(applications)
        connection.with_lock do
          retained_ids = applications.map { |application| application.fetch(:provider_page_id) }
          existing = connection.applications.index_by(&:provider_page_id)

          applications.each do |attributes|
            application = existing.fetch(attributes.fetch(:provider_page_id)) do
              connection.applications.build
            end
            application.assign_attributes(attributes)
            application.save!
          end

          stale = NotionApplication.where(notion_connection: connection)
          stale = stale.where.not(provider_page_id: retained_ids) if retained_ids.any?
          stale.delete_all
          connection.applications.reset
          connection.update!(
            last_synced_at: now,
            last_synced_through_on: current_date,
            last_sync_error: nil
          )
        end
      end

      def record_failure(message)
        connection.with_lock do
          connection.update!(last_sync_error: message)
        end
      rescue ActiveRecord::RecordNotFound
        nil
      end
  end
end
