module Notion
  class ActivityHeatmapPresenter
    Cell = Data.define(
      :date,
      :week,
      :weekday,
      :state,
      :level,
      :application_count,
      :application_details,
      :status_change_count,
      :status_change_details,
      :selected,
      :date_label,
      :aria_label,
      :detail_message
    )

    STATUS_TONE_PATTERNS = {
      negative: /\b(reject(?:ed|ion)?|declin(?:ed)?|unsuccessful|not selected)\b/i,
      positive: /\b(applied|submitted|offer(?:ed| received)?|accepted|hired)\b/i,
      progress: /\b(interview(?:ing|ed)?|screen(?:ing)?|assessment|challenge|test)\b/i
    }.freeze

    def initialize(connection:, calendar:, applications:, status_changes:)
      @connection = connection
      @calendar = calendar
      @applications = applications
      @status_changes = status_changes
    end

    def cells
      @cells ||= calendar.dates_through_today.map do |date|
        daily_applications = applications.fetch(date, [])
        daily_status_changes = status_changes.fetch(date, [])
        state = state_for(date, daily_applications)
        count = count_for(state, daily_applications)

        Cell.new(
          date:,
          week: calendar.week_for(date),
          weekday: date.wday,
          state:,
          level: level_for(count),
          application_count: count,
          application_details: application_details(daily_applications),
          status_change_count: daily_status_changes.length,
          status_change_details: status_change_details(daily_status_changes),
          selected: date == calendar.today,
          date_label: date.to_fs(:long),
          aria_label: aria_label(date, state, count, daily_status_changes.length),
          detail_message: detail_message(state)
        )
      end
    end

    private
      attr_reader :connection, :calendar, :applications, :status_changes

      def state_for(date, daily_applications)
        return "untracked" if connection.nil? || date < connection.tracking_started_on
        return "unsynchronized" if connection.last_synced_through_on.nil? || date > connection.last_synced_through_on
        return "zero" if daily_applications.empty?

        "active"
      end

      def count_for(state, daily_applications)
        return if %w[untracked unsynchronized].include?(state)

        daily_applications.length
      end

      def level_for(count)
        case count
        when nil, 0 then "none"
        when 1 then "first"
        when 2 then "second"
        when 3..4 then "third"
        else "fourth"
        end
      end

      def aria_label(date, state, count, status_change_count)
        prefix = date.to_fs(:long)
        activity_label = case state
        when "untracked" then "#{prefix}: not tracked"
        when "unsynchronized" then "#{prefix}: not synchronized"
        when "zero" then "#{prefix}: 0 applications; synchronized"
        else "#{prefix}: #{count} #{"application".pluralize(count)}"
        end
        return activity_label if status_change_count.zero?

        "#{activity_label}; #{status_change_count} application #{"change".pluralize(status_change_count)} detected"
      end

      def detail_message(state)
        case state
        when "untracked"
          "This date is before Notion tracking began and is not tracked."
        when "unsynchronized"
          "This date is tracked but Notion applications have not been updated yet."
        when "zero"
          "Notion was synchronized with no applications submitted on this date."
        else
          "Applications remain on their Application Date; the badge shows the first status Grindfolio observed."
        end
      end

      def application_details(daily_applications)
        daily_applications.map do |application|
          status = first_observed_status(application)

          {
            company_name: application.company_name,
            role: application.role.presence,
            status:,
            status_tone: status_tone(status)
          }
        end
      end

      def first_observed_status(application)
        first_change = application.status_changes&.first
        first_change ? first_change.from_status.presence : application.current_status.presence
      end

      def status_tone(status)
        return "neutral" if status.blank?

        match = STATUS_TONE_PATTERNS.find { |_tone, pattern| status.match?(pattern) }
        match ? match.first.to_s : "neutral"
      end

      def status_change_details(daily_status_changes)
        daily_status_changes.map do |change|
          application = change.notion_application
          from_status = change.from_status.presence || "No status"
          to_status = change.to_status.presence || "No status"

          {
            company_name: application.company_name,
            role: application.role.presence,
            from_status:,
            from_status_tone: status_tone(change.from_status),
            to_status:,
            to_status_tone: status_tone(change.to_status)
          }
        end
      end
  end
end
