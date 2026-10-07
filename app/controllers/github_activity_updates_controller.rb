class GithubActivityUpdatesController < ApplicationController
  UPDATE_COMPLETED_MESSAGE = "GitHub activity update completed."
  UPDATE_FAILED_MESSAGE = "GitHub activity could not be updated. Your existing activity is still available."

  before_action :require_authentication
  protect_from_forgery with: :exception

  def show
    load_dashboard_state
    @github_notification = terminal_notification

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path, status: :see_other }
    end
  end

  def create
    @github_connection = current_github_connection
    return render_without_connection unless @github_connection

    notification = Github::RequestActivityUpdate.new(connection: @github_connection).call
    @github_update_message = notification&.fetch(:message)
    render_update(status: notification ? :ok : :accepted, notification:)
  end

  private
    def current_github_connection
      Current.user.external_identities.github.includes(:github_connection).first&.github_connection
    end

    def render_without_connection
      @github_update_message = "Connect GitHub before updating activity."
      render_update(notification: { type: :alert, message: @github_update_message })
    end

    def render_update(status: :ok, notification: nil)
      load_dashboard_state
      @github_notification = notification

      respond_to do |format|
        format.turbo_stream { render :show, status: }
        format.html do
          redirect_options = { status: :see_other }
          redirect_options[notification[:type]] = notification[:message] if notification
          redirect_to root_path, **redirect_options
        end
      end
    end

    def terminal_notification
      if @github_connection&.sync_status_ready? && @github_connection.last_synced_at?
        { type: :notice, message: UPDATE_COMPLETED_MESSAGE }
      elsif @github_connection&.sync_status_error?
        { type: :alert, message: UPDATE_FAILED_MESSAGE }
      elsif @github_connection&.sync_status_reauthorization_required?
        { type: :alert, message: Github::SyncContributions::REAUTHORIZATION_REQUIRED_MESSAGE }
      end
    end

    def load_dashboard_state
      @github_identity = Current.user.external_identities.github.first
      @github_connection = @github_identity&.github_connection
      @display_time_zone = Current.user.time_zone.presence || "UTC"
      @github_today = Time.current.in_time_zone(@display_time_zone).to_date
      @heatmap_calendar = ActivityHeatmapCalendar.new(today: @github_today)
      @github_contributions = contributions_in_heatmap_range
      @tracking_started_on = @github_connection&.tracking_started_on
    end

    def contributions_in_heatmap_range
      return {} unless @github_connection

      @github_connection.daily_contributions
        .where(activity_date: @heatmap_calendar.dates)
        .index_by(&:activity_date)
    end
end
