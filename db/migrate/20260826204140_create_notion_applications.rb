class CreateNotionApplications < ActiveRecord::Migration[8.1]
  def change
    change_table :notion_connections, bulk: true do |t|
      t.datetime :last_synced_at
      t.text :last_sync_error
    end

    create_table :notion_applications do |t|
      t.references :notion_connection, null: false, foreign_key: true
      t.string :provider_page_id, null: false
      t.date :applied_on, null: false
      t.text :company_name, null: false
      t.text :role
      t.string :current_status
      t.datetime :provider_last_edited_at, null: false

      t.timestamps
    end

    add_index :notion_applications,
      [ :notion_connection_id, :provider_page_id ],
      unique: true,
      name: "index_notion_applications_on_connection_and_page"
    add_index :notion_applications,
      [ :notion_connection_id, :applied_on ],
      name: "index_notion_applications_on_connection_and_date"
    add_check_constraint :notion_applications,
      "provider_page_id <> ''",
      name: "notion_applications_provider_page_id_present"
    add_check_constraint :notion_applications,
      "company_name <> ''",
      name: "notion_applications_company_name_present"
  end
end
