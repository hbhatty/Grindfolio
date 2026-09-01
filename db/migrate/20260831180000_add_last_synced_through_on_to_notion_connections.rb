class AddLastSyncedThroughOnToNotionConnections < ActiveRecord::Migration[8.1]
  class BackfillConnection < ActiveRecord::Base
    self.table_name = "notion_connections"
  end

  class BackfillUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    add_column :notion_connections, :last_synced_through_on, :date
    BackfillConnection.reset_column_information

    BackfillConnection.where.not(last_synced_at: nil).find_each do |connection|
      time_zone = BackfillUser.where(id: connection.user_id).pick(:time_zone).presence || "UTC"
      connection.update_columns(
        last_synced_through_on: connection.last_synced_at.in_time_zone(time_zone).to_date
      )
    end
  end

  def down
    remove_column :notion_connections, :last_synced_through_on
  end
end
