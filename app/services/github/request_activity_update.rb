module Github
  class RequestActivityUpdate
    ENQUEUE_COOLDOWN = 5.minutes
    ENQUEUE_FAILURE_MESSAGE = "GitHub activity could not start. Try again."
    COOLDOWN_MESSAGE = "GitHub activity was recently updated. Please wait before updating again."

    def initialize(connection:)
      @connection = connection
    end

    def call
      case claim_update
      when :accepted
        return if enqueue_update

        recover_enqueue_failure
        { type: :alert, message: ENQUEUE_FAILURE_MESSAGE }
      when :already_updating
        { type: :notice, message: "GitHub activity is already updating." }
      when :reauthorization_required
        { type: :alert, message: SyncContributions::REAUTHORIZATION_REQUIRED_MESSAGE }
      when :cooldown
        { type: :notice, message: COOLDOWN_MESSAGE }
      end
    end

    private
      attr_reader :connection

      def claim_update
        connection.with_lock do
          if connection.sync_status_queued? || connection.sync_status_syncing?
            :already_updating
          elsif connection.sync_status_reauthorization_required?
            :reauthorization_required
          elsif !Rails.cache.write(cooldown_cache_key, true, expires_in: ENQUEUE_COOLDOWN, unless_exist: true)
            :cooldown
          else
            connection.update!(sync_status: "queued", last_sync_error: nil)
            :accepted
          end
        end
      end

      def cooldown_cache_key
        "github-activity-update:github-connection:#{connection.id}"
      end

      def enqueue_update
        SyncContributionsJob.perform_later(connection.id).present?
      rescue ActiveJob::EnqueueError => error
        Rails.logger.error(
          "GitHub synchronization enqueue failed for connection #{connection.id} (#{error.class.name})"
        )
        false
      end

      def recover_enqueue_failure
        Rails.cache.delete(cooldown_cache_key)
        GithubConnection.where(id: connection.id, sync_status: "queued").update_all(
          sync_status: "error",
          last_sync_error: ENQUEUE_FAILURE_MESSAGE,
          updated_at: Time.current
        )
        connection.reload
      end
  end
end
