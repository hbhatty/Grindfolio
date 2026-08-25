class CreateLeetcodeVerificationDataModel < ActiveRecord::Migration[8.1]
  def change
    create_table :leetcode_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :username, null: false
      t.date :tracking_started_on, null: false
      t.datetime :verified_at, null: false

      t.timestamps
    end

    add_index :leetcode_connections,
      "lower(username)",
      unique: true,
      name: "index_leetcode_connections_on_lower_username"
    add_check_constraint :leetcode_connections,
      "username <> ''",
      name: "leetcode_connections_username_present"

    create_table :leetcode_verification_challenges do |t|
      t.references :user, null: false, foreign_key: true
      t.string :requested_username, null: false
      t.text :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.integer :verification_attempts, null: false, default: 0

      t.timestamps
    end

    add_index :leetcode_verification_challenges, :expires_at
    add_check_constraint :leetcode_verification_challenges,
      "requested_username <> ''",
      name: "leetcode_verification_challenges_username_present"
    add_check_constraint :leetcode_verification_challenges,
      "token <> ''",
      name: "leetcode_verification_challenges_token_present"
    add_check_constraint :leetcode_verification_challenges,
      "verification_attempts BETWEEN 0 AND 5",
      name: "leetcode_verification_challenges_attempts_in_range"
  end
end
