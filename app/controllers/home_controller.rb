class HomeController < ApplicationController
  def index
    return unless Current.user

    @github_identity = Current.user.external_identities.github.first
    @github_connection = @github_identity&.github_connection
    @display_time_zone = Current.user.time_zone.presence || "UTC"
    @github_today = Time.current.in_time_zone(@display_time_zone).to_date
    @heatmap_calendar = ActivityHeatmapCalendar.new(today: @github_today)
    @github_contributions = contributions_in_heatmap_range
    @tracking_started_on = @github_connection&.tracking_started_on
    @leetcode_connection = Current.user.leetcode_connection
    @leetcode_today = Time.current.utc.to_date
    @leetcode_heatmap_calendar = ActivityHeatmapCalendar.new(today: @leetcode_today)
    @leetcode_activities = leetcode_activities_in_heatmap_range
    @leetcode_heatmap = Leetcode::ActivityHeatmapPresenter.new(
      connection: @leetcode_connection,
      calendar: @leetcode_heatmap_calendar,
      activities: @leetcode_activities
    )
    @notion_connection = Current.user.notion_connection
    @notion_applications = notion_applications_in_heatmap_range
    @notion_heatmap = Notion::ActivityHeatmapPresenter.new(
      connection: @notion_connection,
      calendar: @heatmap_calendar,
      applications: @notion_applications
    )
  end

  private
    def contributions_in_heatmap_range
      return {} unless @github_connection

      @github_connection.daily_contributions
        .where(activity_date: @heatmap_calendar.dates)
        .index_by(&:activity_date)
    end

    def leetcode_activities_in_heatmap_range
      return {} unless @leetcode_connection

      @leetcode_connection.daily_activities
        .where(activity_date: @leetcode_heatmap_calendar.dates)
        .index_by(&:activity_date)
    end

    def notion_applications_in_heatmap_range
      return {} unless @notion_connection

      @notion_connection.applications
        .where(applied_on: @heatmap_calendar.dates)
        .order(:applied_on, :company_name)
        .group_by(&:applied_on)
    end
end
