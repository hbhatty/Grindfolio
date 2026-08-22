class CreateGithubConnectionDataModel < ActiveRecord::Migration[8.1]
  def change
    create_table :external_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :provider_uid, null: false
      t.string :provider_username
      t.string :provider_email
      t.string :profile_image_url
      t.datetime :login_enabled_at

      t.timestamps
    end

    add_index :external_identities,
      %i[provider provider_uid],
      unique: true
    add_index :external_identities,
      %i[user_id provider],
      unique: true
    add_check_constraint :external_identities,
      "provider <> ''",
      name: "external_identities_provider_present"
    add_check_constraint :external_identities,
      "provider_uid <> ''",
      name: "external_identities_provider_uid_present"

    create_table :github_connections do |t|
      t.references :external_identity,
        null: false,
        foreign_key: true,
        index: { unique: true }
      t.date :tracking_started_on, null: false
      t.string :sync_status, null: false, default: "pending"
      t.datetime :last_synced_at
      t.text :last_sync_error

      t.timestamps
    end

    add_check_constraint :github_connections,
      "sync_status IN ('pending', 'syncing', 'ready', 'error')",
      name: "github_connections_valid_sync_status"

    create_table :github_daily_contributions do |t|
      t.references :github_connection, null: false, foreign_key: true
      t.date :activity_date, null: false
      t.integer :contribution_count, null: false, default: 0
      t.string :contribution_level, null: false, default: "NONE"

      t.timestamps
    end

    add_index :github_daily_contributions,
      %i[github_connection_id activity_date],
      unique: true,
      name: "index_github_daily_contributions_on_connection_and_date"
    add_check_constraint :github_daily_contributions,
      "contribution_count >= 0",
      name: "github_daily_contributions_nonnegative_count"
    add_check_constraint :github_daily_contributions,
      "contribution_level IN ('NONE', 'FIRST_QUARTILE', 'SECOND_QUARTILE', 'THIRD_QUARTILE', 'FOURTH_QUARTILE')",
      name: "github_daily_contributions_valid_level"
  end
end
