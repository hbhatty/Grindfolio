module Github
  class SyncContributions
    class Error < StandardError; end
    class AlreadySyncing < Error; end
    class IdentityMismatch < Error; end
    class InvalidCalendar < Error; end
    class ReauthorizationRequired < Error; end

    Result = Data.define(:from_date, :to_date, :days_synchronized, :synced_at)

    RECONCILIATION_DAYS = 30
    STORED_ERROR_MESSAGE = "GitHub activity could not be updated. Try again."
    REAUTHORIZATION_REQUIRED_MESSAGE = "Reconnect GitHub to continue updating activity."

    def initialize(
      connection:,
      today: nil,
      now: Time.current,
      calendar_client: Github::ContributionCalendar,
      access_token_client: Github::AccessToken,
      require_queued: false
    )
      @connection = connection
      @now = now
      @today = (today || default_today).to_date
      @calendar_client = calendar_client
      @access_token_client = access_token_client
      @require_queued = require_queued
      @sync_started = false
    end

    def call
      start_sync!
      result = fetch_calendar
      validate_identity!(result)
      rows = build_rows(result)
      persist_result!(result, rows)
    rescue AlreadySyncing
      raise
    rescue IdentityMismatch, InvalidCalendar => error
      mark_failed!(error)
      raise
    rescue Github::AccessToken::ReauthorizationRequired => error
      mark_failed!(error, status: "reauthorization_required")
      raise ReauthorizationRequired, "GitHub reauthorization is required", cause: error
    rescue Github::ContributionCalendar::Error,
      Github::AccessToken::Error,
      ActiveRecord::ActiveRecordError,
      ActiveRecord::Encryption::Errors::Decryption,
      KeyError,
      ArgumentError,
      TypeError => error
      mark_failed!(error)
      raise Error, "GitHub contributions could not be synchronized", cause: error
    end

    private
      attr_reader :connection, :today, :now, :calendar_client, :access_token_client, :require_queued

      def default_today
        now.in_time_zone(connection.user.time_zone.presence || "UTC").to_date
      end

      def start_sync!
        connection.with_lock do
          if require_queued
            unless connection.sync_status_queued?
              raise AlreadySyncing, "GitHub connection is no longer queued"
            end
          elsif connection.sync_status_queued? || connection.sync_status_syncing?
            raise AlreadySyncing, "GitHub connection is already scheduled or synchronizing"
          end

          connection.update_columns(
            sync_status: "syncing",
            last_sync_error: nil,
            updated_at: now
          )
          @sync_started = true
        end
      end

      def fetch_calendar
        calendar_client.new(
          access_token: access_token_client.new(connection:, now:).call,
          from_date: from_date - 1.day,
          to_date: today + 1.day
        ).call
      end

      def from_date
        @from_date ||= [ connection.tracking_started_on, today - (RECONCILIATION_DAYS - 1).days ].max
      end

      def validate_identity!(result)
        provider_uid = result.fetch(:github_database_id).to_s
        return if provider_uid == connection.external_identity.provider_uid

        raise IdentityMismatch, "GitHub token belongs to a different account"
      end

      def build_rows(result)
        seen_dates = {}

        result.fetch(:days).filter_map do |day|
          activity_date = normalize_date(day.fetch(:activity_date))
          next unless activity_date.between?(from_date, today)

          raise InvalidCalendar, "GitHub returned a duplicate calendar date" if seen_dates[activity_date]

          seen_dates[activity_date] = true
          build_row(day, activity_date)
        end
      end

      def normalize_date(value)
        value.respond_to?(:to_date) ? value.to_date : Date.iso8601(value.to_s)
      end

      def build_row(day, activity_date)
        contribution_count = Integer(day.fetch(:contribution_count))
        contribution_level = day.fetch(:contribution_level).to_s

        if contribution_count.negative? || !GithubDailyContribution::LEVELS.include?(contribution_level)
          raise InvalidCalendar, "GitHub returned an invalid daily contribution"
        end

        {
          github_connection_id: connection.id,
          activity_date:,
          contribution_count:,
          contribution_level:,
          created_at: now,
          updated_at: now
        }
      end

      def persist_result!(result, rows)
        GithubConnection.transaction do
          locked_connection = GithubConnection.lock.find(connection.id)
          unless locked_connection.sync_status_syncing?
            raise Error, "GitHub synchronization state changed before persistence"
          end

          upsert_rows(rows)
          locked_connection.external_identity.update_columns(
            provider_username: result.fetch(:github_login),
            updated_at: now
          )
          locked_connection.update_columns(
            sync_status: "ready",
            last_synced_at: now,
            last_sync_error: nil,
            updated_at: now
          )
        end

        connection.reload
        Result.new(
          from_date:,
          to_date: today,
          days_synchronized: rows.length,
          synced_at: now
        )
      end

      def upsert_rows(rows)
        return if rows.empty?

        GithubDailyContribution.upsert_all(
          rows,
          unique_by: :index_github_daily_contributions_on_connection_and_date,
          update_only: %i[contribution_count contribution_level updated_at],
          record_timestamps: false
        )
      end

      def mark_failed!(error, status: "error")
        return unless @sync_started

        stored_message = status == "reauthorization_required" ?
          REAUTHORIZATION_REQUIRED_MESSAGE :
          STORED_ERROR_MESSAGE

        GithubConnection.where(id: connection.id, sync_status: "syncing").update_all(
          sync_status: status,
          last_sync_error: stored_message,
          updated_at: now
        )
        connection.reload
        Rails.logger.warn(
          "GitHub synchronization failed for connection #{connection.id} (#{error.class.name})"
        )
      end
  end
end
