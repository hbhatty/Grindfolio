class GithubActivityUpdatesController < ApplicationController
  ENQUEUE_COOLDOWN = 5.minutes
  ENQUEUE_FAILURE_MESSAGE = "GitHub activity could not start. Try again."

  before_action :require_authentication
  protect_from_forgery with: :exception

  def show
    load_dashboard_state

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path, status: :see_other }
    end
  end

  def create
    @github_connection = current_github_connection
    return render_without_connection unless @github_connection

    case claim_update(@github_connection)
    when :accepted
      if enqueue_update(@github_connection)
        render_update(status: :accepted)
      else
        recover_enqueue_failure(@github_connection)
        @github_update_message = ENQUEUE_FAILURE_MESSAGE
        render_update
      end
    when :already_updating
      @github_update_message = "GitHub activity is already updating."
      render_update
    when :reauthorization_required
      @github_update_message = Github::SyncContributions::REAUTHORIZATION_REQUIRED_MESSAGE
      render_update
    when :cooldown
      @github_update_message = "Please wait a few minutes before trying again."
      render_update(html_notice: @github_update_message)
    end
  end

  private
    def current_github_connection
      Current.user.external_identities.github.includes(:github_connection).first&.github_connection
    end

    def claim_update(connection)
      connection.with_lock do
        if connection.sync_status_queued? || connection.sync_status_syncing?
          :already_updating
        elsif connection.sync_status_reauthorization_required?
          :reauthorization_required
        elsif !claim_cooldown(cooldown_cache_key(connection))
          :cooldown
        else
          connection.update!(
            sync_status: "queued",
            last_sync_error: nil
          )
          :accepted
        end
      end
    end

    def cooldown_cache_key(connection)
      "github-activity-update:github-connection:#{connection.id}"
    end

    def claim_cooldown(cooldown_key)
      Rails.cache.write(
        cooldown_key,
        true,
        expires_in: ENQUEUE_COOLDOWN,
        unless_exist: true
      )
    end

    def enqueue_update(connection)
      Github::SyncContributionsJob.perform_later(connection.id).present?
    rescue ActiveJob::EnqueueError => error
      Rails.logger.error(
        "GitHub synchronization enqueue failed for connection #{connection.id} (#{error.class.name})"
      )
      false
    end

    def recover_enqueue_failure(connection)
      Rails.cache.delete(cooldown_cache_key(connection))
      GithubConnection.where(id: connection.id, sync_status: "queued").update_all(
        sync_status: "error",
        last_sync_error: ENQUEUE_FAILURE_MESSAGE,
        updated_at: Time.current
      )
      connection.reload
    end

    def render_without_connection
      @github_update_message = "Connect GitHub before updating activity."
      render_update(html_alert: @github_update_message)
    end

    def render_update(status: :ok, html_notice: nil, html_alert: nil)
      load_dashboard_state

      respond_to do |format|
        format.turbo_stream { render :show, status: }
        format.html do
          redirect_options = { status: :see_other }
          redirect_options[:notice] = html_notice if html_notice
          redirect_options[:alert] = html_alert if html_alert
          redirect_to root_path, **redirect_options
        end
      end
    end

    def load_dashboard_state
      @github_identity = Current.user.external_identities.github.first
      @github_connection = @github_identity&.github_connection
      @display_time_zone = Current.user.time_zone.presence || "UTC"
      @github_today = Time.current.in_time_zone(@display_time_zone).to_date
      @heatmap_start_date = @github_today.beginning_of_week(:sunday) - 52.weeks
      @heatmap_end_date = @heatmap_start_date + 370.days
      @github_contributions = contributions_in_heatmap_range
      @tracking_started_on = @github_connection&.tracking_started_on
    end

    def contributions_in_heatmap_range
      return {} unless @github_connection

      @github_connection.daily_contributions
        .where(activity_date: @heatmap_start_date..@heatmap_end_date)
        .index_by(&:activity_date)
    end
end
