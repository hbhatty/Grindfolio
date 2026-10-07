class NotionActivityUpdatesController < ApplicationController
  class_attribute :sync_service, default: Notion::SyncApplications

  before_action :require_authentication
  protect_from_forgery with: :exception

  def create
    connection = Current.user.notion_connection
    unless connection
      return redirect_to root_path,
        alert: "Connect Notion before updating activity.",
        status: :see_other
    end

    notification = Notion::RequestActivityUpdate.new(connection:, sync_service:).call
    redirect_to root_path, status: :see_other, notification[:type] => notification[:message]
  end
end
