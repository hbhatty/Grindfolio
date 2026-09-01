module Notion
  class ActivityHeatmapPresenter
    Cell = Data.define(
      :date,
      :week,
      :weekday,
      :state,
      :level,
      :application_count,
      :selected,
      :date_label,
      :aria_label,
      :detail_message
    )

    def initialize(connection:, calendar:, applications:)
      @connection = connection
      @calendar = calendar
      @applications = applications
    end

    def cells
      @cells ||= calendar.dates_through_today.map do |date|
        daily_applications = applications.fetch(date, [])
        state = state_for(date, daily_applications)
        count = count_for(state, daily_applications)

        Cell.new(
          date:,
          week: calendar.week_for(date),
          weekday: date.wday,
          state:,
          level: level_for(count),
          application_count: count,
          selected: date == calendar.today,
          date_label: date.to_fs(:long),
          aria_label: aria_label(date, state, count),
          detail_message: detail_message(state, daily_applications)
        )
      end
    end

    private
      attr_reader :connection, :calendar, :applications

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

      def aria_label(date, state, count)
        prefix = date.to_fs(:long)

        case state
        when "untracked" then "#{prefix}: not tracked"
        when "unsynchronized" then "#{prefix}: not synchronized"
        when "zero" then "#{prefix}: 0 applications; synchronized"
        else "#{prefix}: #{count} #{"application".pluralize(count)}"
        end
      end

      def detail_message(state, daily_applications)
        case state
        when "untracked"
          "This date is before Notion tracking began and is not tracked."
        when "unsynchronized"
          "This date is tracked but Notion applications have not been updated yet."
        when "zero"
          "Notion was synchronized with no applications submitted on this date."
        else
          daily_applications.map { |application| application_detail(application) }.join(" · ")
        end
      end

      def application_detail(application)
        details = [ application.company_name ]
        details << application.role if application.role.present?
        details << "Status: #{application.current_status}" if application.current_status.present?
        details.join(" — ")
      end
  end
end
