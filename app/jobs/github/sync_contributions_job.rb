module Github
  class SyncContributionsJob < ApplicationJob
    def perform(connection_id)
      connection = GithubConnection.find_by(id: connection_id)
      return unless connection

      Github::SyncContributions.new(connection:, require_queued: true).call
    rescue Github::SyncContributions::AlreadySyncing
      nil
    end
  end
end
