class ExpandGithubSyncLifecycleStates < ActiveRecord::Migration[8.1]
  CONSTRAINT_NAME = "github_connections_valid_sync_status"

  def up
    remove_check_constraint :github_connections, name: CONSTRAINT_NAME
    add_check_constraint :github_connections,
      "sync_status IN ('pending', 'queued', 'syncing', 'ready', 'error', 'reauthorization_required')",
      name: CONSTRAINT_NAME
  end

  def down
    execute <<~SQL.squish
      UPDATE github_connections
      SET sync_status = CASE
        WHEN sync_status = 'reauthorization_required' THEN 'error'
        ELSE 'pending'
      END
      WHERE sync_status IN ('queued', 'reauthorization_required')
    SQL

    remove_check_constraint :github_connections, name: CONSTRAINT_NAME
    add_check_constraint :github_connections,
      "sync_status IN ('pending', 'syncing', 'ready', 'error')",
      name: CONSTRAINT_NAME
  end
end
