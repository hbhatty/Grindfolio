class NotionActivityUpdatesController < ApplicationController
  CONNECTION_COOLDOWN = 5.minutes

  class_attribute :sync_service, default: Notion::SyncApplications

  before_action :require_authentication
  protect_from_forgery with: :exception

  def create
    connection = Current.user.notion_connection
    return redirect_without_connection unless connection
    return redirect_during_cooldown unless claim_update(connection)

    sync_service.call(connection:)
    redirect_to root_path,
      notice: "Notion activity update completed.",
      status: :see_other
  rescue Notion::SyncApplications::UnsupportedTemplate
    redirect_to root_path,
      alert: "That Notion tracker is not supported by the current proof. Your saved activity is unchanged.",
      status: :see_other
  rescue Notion::SyncApplications::ReauthorizationRequired
    redirect_to root_path,
      alert: "Reauthorize Notion before updating activity. Your saved activity is unchanged.",
      status: :see_other
  rescue Notion::SyncApplications::Error
    redirect_to root_path,
      alert: "Notion activity could not be updated. Your saved activity is still available.",
      status: :see_other
  end

  private
    def claim_update(connection)
      Rails.cache.write(
        "notion-activity-update:notion-connection:#{connection.id}",
        true,
        expires_in: CONNECTION_COOLDOWN,
        unless_exist: true
      )
    end

    def redirect_without_connection
      redirect_to root_path,
        alert: "Connect Notion before updating activity.",
        status: :see_other
    end

    def redirect_during_cooldown
      redirect_to root_path,
        notice: "Notion activity was recently updated. Please wait before updating again.",
        status: :see_other
    end
end
