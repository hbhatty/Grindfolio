class ActivityUpdatesController < ApplicationController
  before_action :require_authentication
  protect_from_forgery with: :exception

  def create
    github_connection = Current.user.external_identities.github.first&.github_connection
    updates = [
      [ Github::RequestActivityUpdate, github_connection ],
      [ Leetcode::RequestActivityUpdate, Current.user.leetcode_connection ],
      [ Notion::RequestActivityUpdate, Current.user.notion_connection ]
    ].filter_map do |service, connection|
      next unless connection

      service.new(connection:).call || { type: :notice, message: "GitHub activity update started." }
    end

    if updates.empty?
      return redirect_to root_path, status: :see_other,
        alert: "Connect a service before updating activity."
    end

    updates.group_by { |notification| notification[:type] }.each do |type, notifications|
      flash[type] = notifications.map { |notification| notification[:message] }.join(" ")
    end
    redirect_to root_path, status: :see_other
  end
end
