class CreateNotionApplicationStatusChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :notion_application_status_changes do |t|
      t.references :notion_application,
        null: false,
        foreign_key: { on_delete: :cascade }
      t.string :from_status
      t.string :to_status
      t.date :detected_on, null: false
      t.datetime :detected_at, null: false

      t.timestamps
    end

    add_index :notion_application_status_changes, :detected_on
    add_check_constraint :notion_application_status_changes,
      "from_status IS NULL OR from_status <> ''",
      name: "notion_status_changes_from_status_present"
    add_check_constraint :notion_application_status_changes,
      "to_status IS NULL OR to_status <> ''",
      name: "notion_status_changes_to_status_present"
    add_check_constraint :notion_application_status_changes,
      "from_status IS DISTINCT FROM to_status",
      name: "notion_status_changes_status_changed"
  end
end
