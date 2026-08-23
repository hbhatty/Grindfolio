class HomeController < ApplicationController
  def index
    return unless Current.user

    @github_identity = Current.user.external_identities.github.first
    @github_connection = @github_identity&.github_connection
    @display_time_zone = Current.user.time_zone.presence || "UTC"
    @github_today = Time.current.in_time_zone(@display_time_zone).to_date
    @heatmap_start_date = @github_today.beginning_of_week(:sunday) - 52.weeks
    @heatmap_end_date = @heatmap_start_date + 370.days
    @github_contributions = contributions_in_heatmap_range
    @tracking_started_on = @github_connection&.tracking_started_on
  end

  private
    def contributions_in_heatmap_range
      return {} unless @github_connection

      @github_connection.daily_contributions
        .where(activity_date: @heatmap_start_date..@heatmap_end_date)
        .index_by(&:activity_date)
    end
end
