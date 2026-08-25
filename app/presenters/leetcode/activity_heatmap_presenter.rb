module Leetcode
  class ActivityHeatmapPresenter
    Cell = Data.define(
      :date,
      :week,
      :weekday,
      :state,
      :level,
      :submission_count,
      :selected,
      :date_label,
      :aria_label,
      :detail_message
    )

    attr_reader :start_date, :end_date

    def initialize(connection:, today:, start_date:, end_date:, activities:)
      @connection = connection
      @today = today
      @start_date = start_date
      @end_date = end_date
      @activities = activities
    end

    def cells
      @cells ||= (start_date..end_date).map.with_index do |date, index|
        activity = activities[date]
        count = activity&.submission_count
        state = state_for(date, activity)

        Cell.new(
          date:,
          week: index / 7,
          weekday: date.wday,
          state:,
          level: level_for(count),
          submission_count: count,
          selected: date == today,
          date_label: date_label(date),
          aria_label: aria_label(date, state, count),
          detail_message: detail_message(state, count)
        )
      end
    end

    private
      attr_reader :connection, :today, :activities

      def state_for(date, activity)
        return "future" if date > today
        return "untracked" if connection.nil? || date < connection.tracking_started_on
        return "unsynchronized" unless activity
        return "zero" if activity.submission_count.zero?

        "active"
      end

      def level_for(count)
        case count
        when nil, 0 then "none"
        when 1..2 then "first"
        when 3..5 then "second"
        when 6..9 then "third"
        else "fourth"
        end
      end

      def date_label(date)
        "#{date.to_fs(:long)} — LeetCode date (UTC)"
      end

      def aria_label(date, state, count)
        prefix = date_label(date)

        case state
        when "future"
          "#{prefix}: future date"
        when "untracked"
          "#{prefix}: not tracked"
        when "unsynchronized"
          "#{prefix}: not synchronized"
        when "zero"
          "#{prefix}: raw submission count 0; synchronized with no submissions"
        else
          "#{prefix}: raw submission count #{count}; active"
        end
      end

      def detail_message(state, count)
        case state
        when "future"
          "This LeetCode date (UTC) has not happened yet."
        when "untracked"
          "This LeetCode date (UTC) is before tracking began and is not tracked."
        when "unsynchronized"
          "This LeetCode date (UTC) is in the tracking window but has not been synchronized."
        when "zero"
          "LeetCode raw submission count: 0. This LeetCode date (UTC) was synchronized with no submissions."
        else
          "LeetCode raw submission count: #{count}. This activity belongs to the displayed LeetCode date (UTC)."
        end
      end
  end
end
