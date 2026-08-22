class CreateUsersAndPasswordCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :time_zone

      t.timestamps
    end

    create_table :password_credentials do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.datetime :email_verified_at

      t.timestamps
    end

    add_index :password_credentials,
      "lower(email_address)",
      unique: true,
      name: "index_password_credentials_on_lower_email_address"
  end
end
