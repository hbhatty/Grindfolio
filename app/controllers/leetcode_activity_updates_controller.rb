class LeetcodeActivityUpdatesController < ApplicationController
  before_action :require_authentication
  protect_from_forgery with: :exception

  def create
    connection = Current.user.leetcode_connection
    unless connection
      return redirect_to root_path,
        alert: "Connect LeetCode before updating activity.",
        status: :see_other
    end

    notification = Leetcode::RequestActivityUpdate.new(connection:).call
    redirect_to root_path, status: :see_other, notification[:type] => notification[:message]
  end
end
