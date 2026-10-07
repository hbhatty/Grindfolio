module Notion
  class RequestActivityUpdate
    CONNECTION_COOLDOWN = 5.minutes

    def initialize(connection:, sync_service: SyncApplications)
      @connection = connection
      @sync_service = sync_service
    end

    def call
      unless claim_update
        return { type: :notice, message: "Notion activity was recently updated. Please wait before updating again." }
      end

      result = sync_service.call(connection:)
      { type: :notice, message: update_notice(result) }
    rescue SyncApplications::UnsupportedTemplate
      { type: :alert, message: "That Notion tracker is not supported by the current proof. Your saved activity is unchanged." }
    rescue SyncApplications::ReauthorizationRequired
      { type: :alert, message: "Reauthorize Notion before updating activity. Your saved activity is unchanged." }
    rescue SyncApplications::Error
      { type: :alert, message: "Notion activity could not be updated. Your saved activity is still available." }
    end

    private
      attr_reader :connection, :sync_service

      def claim_update
        Rails.cache.write(
          "notion-activity-update:notion-connection:#{connection.id}",
          true,
          expires_in: CONNECTION_COOLDOWN,
          unless_exist: true
        )
      end

      def update_notice(result)
        changes = {
          added: result.added_count,
          edited: result.updated_count,
          moved: result.moved_count,
          (result.status_changed_count == 1 ? "status changed" : "statuses changed") => result.status_changed_count,
          removed: result.removed_count
        }.filter_map do |label, count|
          "#{count} #{label}" if count.positive?
        end

        return "Notion applications are already up to date." if changes.empty?

        "Notion applications updated: #{changes.to_sentence}."
      end
  end
end
