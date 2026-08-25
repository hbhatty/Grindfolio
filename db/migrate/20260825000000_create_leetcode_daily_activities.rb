class CreateLeetcodeDailyActivities < ActiveRecord::Migration[8.1]
  def change
    change_table :leetcode_connections, bulk: true do |t|
      t.datetime :last_synced_at
      t.text :last_sync_error
    end

    create_table :leetcode_daily_activities do |t|
      t.references :leetcode_connection, null: false, foreign_key: true
      t.date :activity_date, null: false
      t.integer :submission_count, null: false, default: 0

      t.timestamps
    end

    add_index :leetcode_daily_activities,
      %i[leetcode_connection_id activity_date],
      unique: true,
      name: "index_leetcode_daily_activities_on_connection_and_date"
    add_check_constraint :leetcode_daily_activities,
      "submission_count >= 0",
      name: "leetcode_daily_activities_nonnegative_count"
  end
end
