class LeetcodeActivityUpdatesController < ApplicationController
  CONNECTION_COOLDOWN = 15.minutes
  GLOBAL_REQUEST_GATE = 5.seconds
  GLOBAL_SUSPENSION = 1.hour

  before_action :require_authentication
  protect_from_forgery with: :exception

  def create
    connection = Current.user.leetcode_connection
    return redirect_without_connection unless connection

    case claim_update(connection)
    when :suspended
      redirect_to root_path,
        alert: "LeetCode activity updates are temporarily paused. Try again later.",
        status: :see_other
    when :cooldown
      redirect_to root_path,
        notice: "LeetCode activity was recently updated. Please wait before updating again.",
        status: :see_other
    when :global_gate
      redirect_to root_path,
        notice: "Another LeetCode activity update is in progress. Try again shortly.",
        status: :see_other
    when :accepted
      synchronize(connection)
    end
  end

  private
    def claim_update(connection)
      return :suspended if globally_suspended?

      cooldown_key = connection_cooldown_key(connection)
      return :cooldown unless claim_cache_key(cooldown_key, expires_in: CONNECTION_COOLDOWN)

      unless claim_cache_key(global_gate_key, expires_in: GLOBAL_REQUEST_GATE)
        Rails.cache.delete(cooldown_key)
        return :global_gate
      end

      if globally_suspended?
        Rails.cache.delete(global_gate_key)
        Rails.cache.delete(cooldown_key)
        return :suspended
      end

      :accepted
    end

    def synchronize(connection)
      Leetcode::SyncActivities.new(connection:).call
      redirect_to root_path,
        notice: "LeetCode activity update completed.",
        status: :see_other
    rescue Leetcode::SyncActivities::AccessBlocked
      Rails.cache.write(global_suspension_key, true, expires_in: GLOBAL_SUSPENSION)
      redirect_to root_path,
        alert: "LeetCode temporarily blocked activity updates. Try again later. Your saved activity is still available.",
        status: :see_other
    rescue Leetcode::SyncActivities::Error
      redirect_to root_path,
        alert: "LeetCode activity could not be updated. Your saved activity is still available.",
        status: :see_other
    end

    def redirect_without_connection
      redirect_to root_path,
        alert: "Connect LeetCode before updating activity.",
        status: :see_other
    end

    def globally_suspended?
      Rails.cache.exist?(global_suspension_key)
    end

    def claim_cache_key(key, expires_in:)
      Rails.cache.write(key, true, expires_in:, unless_exist: true)
    end

    def connection_cooldown_key(connection)
      "leetcode-activity-update:leetcode-connection:#{connection.id}"
    end

    def global_gate_key
      "leetcode-activity-update:global-request-gate"
    end

    def global_suspension_key
      "leetcode-activity-update:global-suspension"
    end
end
