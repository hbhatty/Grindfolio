module Leetcode
  class RequestActivityUpdate
    CONNECTION_COOLDOWN = 15.minutes
    GLOBAL_REQUEST_GATE = 5.seconds
    GLOBAL_SUSPENSION = 1.hour

    def initialize(connection:)
      @connection = connection
    end

    def call
      case claim_update
      when :suspended
        { type: :alert, message: "LeetCode activity updates are temporarily paused. Try again later." }
      when :cooldown
        { type: :notice, message: "LeetCode activity was recently updated. Please wait before updating again." }
      when :global_gate
        { type: :notice, message: "Another LeetCode activity update is in progress. Try again shortly." }
      when :accepted
        SyncActivities.new(connection:).call
        { type: :notice, message: "LeetCode activity update completed." }
      end
    rescue SyncActivities::AccessBlocked
      Rails.cache.write(global_suspension_key, true, expires_in: GLOBAL_SUSPENSION)
      { type: :alert, message: "LeetCode temporarily blocked activity updates. Try again later. Your saved activity is still available." }
    rescue SyncActivities::Error
      { type: :alert, message: "LeetCode activity could not be updated. Your saved activity is still available." }
    end

    private
      attr_reader :connection

      def claim_update
        return :suspended if globally_suspended?
        return :cooldown unless claim_cache_key(connection_cooldown_key, expires_in: CONNECTION_COOLDOWN)

        unless claim_cache_key(global_gate_key, expires_in: GLOBAL_REQUEST_GATE)
          Rails.cache.delete(connection_cooldown_key)
          return :global_gate
        end

        if globally_suspended?
          Rails.cache.delete(global_gate_key)
          Rails.cache.delete(connection_cooldown_key)
          return :suspended
        end

        :accepted
      end

      def globally_suspended?
        Rails.cache.exist?(global_suspension_key)
      end

      def claim_cache_key(key, expires_in:)
        Rails.cache.write(key, true, expires_in:, unless_exist: true)
      end

      def connection_cooldown_key
        "leetcode-activity-update:leetcode-connection:#{connection.id}"
      end

      def global_gate_key
        "leetcode-activity-update:global-request-gate"
      end

      def global_suspension_key
        "leetcode-activity-update:global-suspension"
      end
  end
end
