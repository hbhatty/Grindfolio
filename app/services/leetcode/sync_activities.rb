module Leetcode
  class SyncActivities
    class Error < StandardError; end
    class AccessBlocked < Error; end
    class IdentityMismatch < Error; end
    class InvalidCalendar < Error; end

    Result = Data.define(:from_date, :to_date, :days_synchronized, :synced_at)

    STORED_ERROR_MESSAGE = "LeetCode activity could not be updated. Try again."

    def initialize(
      connection:,
      today: nil,
      now: Time.current,
      calendar_client: Leetcode::SubmissionCalendar
    )
      @connection = connection
      @now = now
      @today = (today || now.utc.to_date).to_date
      @calendar_client = calendar_client
    end

    def call
      calendar = fetch_calendar
      validate_identity!(calendar)
      counts_by_date = validate_days!(calendar)
      rows = build_rows(counts_by_date)
      persist_result!(rows)
    rescue IdentityMismatch, InvalidCalendar => error
      mark_failed!(error)
      raise
    rescue Leetcode::SubmissionCalendar::AccessBlocked => error
      mark_failed!(error)
      raise AccessBlocked, "LeetCode access controls blocked activity synchronization", cause: error
    rescue Leetcode::SubmissionCalendar::Error,
      ActiveRecord::ActiveRecordError,
      ArgumentError,
      TypeError,
      NoMethodError => error
      mark_failed!(error)
      raise Error, "LeetCode activity could not be synchronized", cause: error
    end

    private
      attr_reader :connection, :today, :now, :calendar_client

      def fetch_calendar
        calendar_client.new(
          username: connection.username,
          year: today.year
        ).call
      end

      def validate_identity!(calendar)
        canonical_username = calendar.username
        return if canonical_username.is_a?(String) && canonical_username == connection.username

        raise IdentityMismatch, "LeetCode returned a different canonical username"
      end

      def validate_days!(calendar)
        days = calendar.days
        unless days.is_a?(Array)
          raise InvalidCalendar, "LeetCode returned an invalid submission calendar"
        end

        days.each_with_object({}) do |day, counts|
          activity_date = day.activity_date
          submission_count = day.submission_count

          unless activity_date.is_a?(Date) && activity_date.year == today.year
            raise InvalidCalendar, "LeetCode returned an invalid submission calendar"
          end
          unless submission_count.is_a?(Integer) && submission_count >= 0
            raise InvalidCalendar, "LeetCode returned an invalid submission calendar"
          end
          if counts.key?(activity_date)
            raise InvalidCalendar, "LeetCode returned a duplicate calendar date"
          end

          counts[activity_date] = submission_count
        end
      end

      def build_rows(counts_by_date)
        return [] if from_date > today

        (from_date..today).map do |activity_date|
          {
            leetcode_connection_id: connection.id,
            activity_date:,
            submission_count: counts_by_date.fetch(activity_date, 0),
            created_at: now,
            updated_at: now
          }
        end
      end

      def from_date
        @from_date ||= [ connection.tracking_started_on, Date.new(today.year, 1, 1) ].max
      end

      def persist_result!(rows)
        LeetcodeConnection.transaction do
          locked_connection = LeetcodeConnection.lock.find(connection.id)
          upsert_rows(rows)
          locked_connection.update_columns(
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

        LeetcodeDailyActivity.upsert_all(
          rows,
          unique_by: :index_leetcode_daily_activities_on_connection_and_date,
          update_only: %i[submission_count updated_at],
          record_timestamps: false
        )
      end

      def mark_failed!(error)
        LeetcodeConnection.where(id: connection.id).update_all(
          last_sync_error: STORED_ERROR_MESSAGE,
          updated_at: now
        )
        connection.reload
        Rails.logger.warn(
          "LeetCode synchronization failed for connection #{connection.id} (#{error.class.name})"
        )
      end
  end
end
