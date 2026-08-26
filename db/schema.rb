# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_26_204140) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "external_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "login_enabled_at"
    t.string "profile_image_url"
    t.string "provider", null: false
    t.string "provider_email"
    t.string "provider_uid", null: false
    t.string "provider_username"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "provider_uid"], name: "index_external_identities_on_provider_and_provider_uid", unique: true
    t.index ["user_id", "provider"], name: "index_external_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_external_identities_on_user_id"
    t.check_constraint "provider::text <> ''::text", name: "external_identities_provider_present"
    t.check_constraint "provider_uid::text <> ''::text", name: "external_identities_provider_uid_present"
  end

  create_table "github_connections", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "access_token_expires_at", null: false
    t.datetime "created_at", null: false
    t.bigint "external_identity_id", null: false
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.text "refresh_token", null: false
    t.datetime "refresh_token_expires_at"
    t.string "sync_status", default: "pending", null: false
    t.date "tracking_started_on", null: false
    t.datetime "updated_at", null: false
    t.index ["external_identity_id"], name: "index_github_connections_on_external_identity_id", unique: true
    t.check_constraint "sync_status::text = ANY (ARRAY['pending'::character varying, 'queued'::character varying, 'syncing'::character varying, 'ready'::character varying, 'error'::character varying, 'reauthorization_required'::character varying]::text[])", name: "github_connections_valid_sync_status"
  end

  create_table "github_daily_contributions", force: :cascade do |t|
    t.date "activity_date", null: false
    t.integer "contribution_count", default: 0, null: false
    t.string "contribution_level", default: "NONE", null: false
    t.datetime "created_at", null: false
    t.bigint "github_connection_id", null: false
    t.datetime "updated_at", null: false
    t.index ["github_connection_id", "activity_date"], name: "index_github_daily_contributions_on_connection_and_date", unique: true
    t.index ["github_connection_id"], name: "index_github_daily_contributions_on_github_connection_id"
    t.check_constraint "contribution_count >= 0", name: "github_daily_contributions_nonnegative_count"
    t.check_constraint "contribution_level::text = ANY (ARRAY['NONE'::character varying, 'FIRST_QUARTILE'::character varying, 'SECOND_QUARTILE'::character varying, 'THIRD_QUARTILE'::character varying, 'FOURTH_QUARTILE'::character varying]::text[])", name: "github_daily_contributions_valid_level"
  end

  create_table "leetcode_connections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.date "tracking_started_on", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "username", null: false
    t.datetime "verified_at", null: false
    t.index "lower((username)::text)", name: "index_leetcode_connections_on_lower_username", unique: true
    t.index ["user_id"], name: "index_leetcode_connections_on_user_id", unique: true
    t.check_constraint "username::text <> ''::text", name: "leetcode_connections_username_present"
  end

  create_table "leetcode_daily_activities", force: :cascade do |t|
    t.date "activity_date", null: false
    t.datetime "created_at", null: false
    t.bigint "leetcode_connection_id", null: false
    t.integer "submission_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["leetcode_connection_id", "activity_date"], name: "index_leetcode_daily_activities_on_connection_and_date", unique: true
    t.index ["leetcode_connection_id"], name: "index_leetcode_daily_activities_on_leetcode_connection_id"
    t.check_constraint "submission_count >= 0", name: "leetcode_daily_activities_nonnegative_count"
  end

  create_table "leetcode_verification_challenges", force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "requested_username", null: false
    t.text "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "verification_attempts", default: 0, null: false
    t.index ["expires_at"], name: "index_leetcode_verification_challenges_on_expires_at"
    t.index ["user_id"], name: "index_leetcode_verification_challenges_on_user_id"
    t.check_constraint "requested_username::text <> ''::text", name: "leetcode_verification_challenges_username_present"
    t.check_constraint "token <> ''::text", name: "leetcode_verification_challenges_token_present"
    t.check_constraint "verification_attempts >= 0 AND verification_attempts <= 5", name: "leetcode_verification_challenges_attempts_in_range"
  end

  create_table "notion_applications", force: :cascade do |t|
    t.date "applied_on", null: false
    t.text "company_name", null: false
    t.datetime "created_at", null: false
    t.string "current_status"
    t.bigint "notion_connection_id", null: false
    t.datetime "provider_last_edited_at", null: false
    t.string "provider_page_id", null: false
    t.text "role"
    t.datetime "updated_at", null: false
    t.index ["notion_connection_id", "applied_on"], name: "index_notion_applications_on_connection_and_date"
    t.index ["notion_connection_id", "provider_page_id"], name: "index_notion_applications_on_connection_and_page", unique: true
    t.index ["notion_connection_id"], name: "index_notion_applications_on_notion_connection_id"
    t.check_constraint "company_name <> ''::text", name: "notion_applications_company_name_present"
    t.check_constraint "provider_page_id::text <> ''::text", name: "notion_applications_provider_page_id_present"
  end

  create_table "notion_connections", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "authorized_at", null: false
    t.string "bot_id", null: false
    t.datetime "created_at", null: false
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.string "owner_user_id"
    t.text "refresh_token", null: false
    t.date "tracking_started_on", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "workspace_id", null: false
    t.string "workspace_name"
    t.index ["bot_id"], name: "index_notion_connections_on_bot_id", unique: true
    t.index ["user_id"], name: "index_notion_connections_on_user_id", unique: true
    t.check_constraint "access_token <> ''::text", name: "notion_connections_access_token_present"
    t.check_constraint "bot_id::text <> ''::text", name: "notion_connections_bot_id_present"
    t.check_constraint "refresh_token <> ''::text", name: "notion_connections_refresh_token_present"
    t.check_constraint "workspace_id::text <> ''::text", name: "notion_connections_workspace_id_present"
  end

  create_table "password_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "email_verified_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "lower((email_address)::text)", name: "index_password_credentials_on_lower_email_address", unique: true
    t.index ["user_id"], name: "index_password_credentials_on_user_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.inet "ip_address"
    t.datetime "last_seen_at", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_sessions_on_expires_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
    t.check_constraint "expires_at > last_seen_at", name: "sessions_expire_after_last_seen"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "time_zone"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "external_identities", "users"
  add_foreign_key "github_connections", "external_identities"
  add_foreign_key "github_daily_contributions", "github_connections"
  add_foreign_key "leetcode_connections", "users"
  add_foreign_key "leetcode_daily_activities", "leetcode_connections"
  add_foreign_key "leetcode_verification_challenges", "users"
  add_foreign_key "notion_applications", "notion_connections"
  add_foreign_key "notion_connections", "users"
  add_foreign_key "password_credentials", "users"
  add_foreign_key "sessions", "users"
end
