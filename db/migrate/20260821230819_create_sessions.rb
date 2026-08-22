class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.inet :ip_address
      t.text :user_agent
      t.datetime :last_seen_at, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :sessions, :expires_at
    add_check_constraint :sessions,
      "expires_at > last_seen_at",
      name: "sessions_expire_after_last_seen"
  end
end
