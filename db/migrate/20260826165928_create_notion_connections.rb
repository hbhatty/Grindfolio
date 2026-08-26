class CreateNotionConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :notion_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :workspace_id, null: false
      t.string :workspace_name
      t.string :bot_id, null: false
      t.string :owner_user_id
      t.text :access_token, null: false
      t.text :refresh_token, null: false
      t.date :tracking_started_on, null: false
      t.datetime :authorized_at, null: false

      t.timestamps
    end

    add_index :notion_connections, :bot_id, unique: true
    add_check_constraint :notion_connections,
      "workspace_id <> ''",
      name: "notion_connections_workspace_id_present"
    add_check_constraint :notion_connections,
      "bot_id <> ''",
      name: "notion_connections_bot_id_present"
    add_check_constraint :notion_connections,
      "access_token <> ''",
      name: "notion_connections_access_token_present"
    add_check_constraint :notion_connections,
      "refresh_token <> ''",
      name: "notion_connections_refresh_token_present"
  end
end
