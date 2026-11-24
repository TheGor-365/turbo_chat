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

ActiveRecord::Schema[8.1].define(version: 2026_11_25_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_account_writing_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "profile_id", limit: 24
    t.string "writing_style", limit: 48, default: "polish_clarity", null: false
    t.string "language", limit: 8, default: "auto", null: false
    t.string "tone", limit: 24, default: "neutral", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_ai_account_writing_preferences_on_user_id", unique: true
  end

  create_table "ai_conversation_goals", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "user_id", null: false
    t.string "purpose", limit: 500, null: false
    t.text "constraints"
    t.string "desired_outcome", limit: 500
    t.integer "revision", default: 1, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id", "user_id"], name: "index_ai_conversation_goals_personal_room_scope", unique: true
    t.index ["room_id"], name: "index_ai_conversation_goals_on_room_id"
    t.index ["user_id"], name: "index_ai_conversation_goals_on_user_id"
  end

  create_table "ai_deliverable_revisions", force: :cascade do |t|
    t.bigint "ai_deliverable_id", null: false
    t.bigint "author_id", null: false
    t.integer "version", null: false
    t.text "body_markdown", null: false
    t.jsonb "source_message_ids", default: [], null: false
    t.string "body_sha256", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_deliverable_id", "version"], name: "index_ai_deliverable_revisions_unique_version", unique: true
    t.index ["author_id"], name: "index_ai_deliverable_revisions_on_author_id"
  end

  create_table "ai_deliverables", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "owner_id", null: false
    t.string "kind", limit: 40, null: false
    t.string "state", limit: 24, default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_ai_deliverables_on_owner_id"
    t.index ["room_id", "owner_id", "created_at"], name: "index_ai_deliverables_room_owner_created"
    t.index ["room_id"], name: "index_ai_deliverables_on_room_id"
  end

  create_table "ai_evidence_review_events", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "message_id", null: false
    t.bigint "reviewer_id", null: false
    t.string "source_version_sha256", limit: 64, null: false
    t.string "stance", limit: 20, null: false
    t.string "request_key", limit: 36, null: false
    t.datetime "created_at", null: false
    t.index ["message_id"], name: "index_ai_evidence_review_events_on_message_id"
    t.index ["reviewer_id", "request_key"], name: "index_ai_evidence_reviews_idempotency", unique: true
    t.index ["reviewer_id"], name: "index_ai_evidence_review_events_on_reviewer_id"
    t.index ["room_id", "message_id", "reviewer_id", "id"], name: "index_ai_evidence_reviews_latest"
    t.index ["room_id"], name: "index_ai_evidence_review_events_on_room_id"
    t.check_constraint "length(source_version_sha256::text) = 64", name: "ai_evidence_reviews_version_length"
    t.check_constraint "stance::text = ANY (ARRAY['acknowledged'::character varying::text, 'disputed'::character varying::text, 'withdrawn'::character varying::text])", name: "ai_evidence_reviews_allowed_stance"
  end

  create_table "ai_personal_enablements", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.boolean "enabled", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_ai_personal_enablements_on_user_id", unique: true
    t.check_constraint "lock_version >= 0", name: "ai_personal_enablements_nonnegative_lock"
  end

  create_table "ai_room_context_consents", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "user_id", null: false
    t.datetime "granted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id", "user_id"], name: "index_ai_room_context_consents_unique_member", unique: true
    t.index ["room_id"], name: "index_ai_room_context_consents_on_room_id"
    t.index ["user_id"], name: "index_ai_room_context_consents_on_user_id"
  end

  create_table "ai_room_shared_writing_preferences", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "editor_id"
    t.string "profile_id", limit: 24
    t.string "writing_style", limit: 48, null: false
    t.string "language", limit: 8, null: false
    t.string "tone", limit: 24, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["editor_id"], name: "index_ai_room_shared_writing_preferences_on_editor_id"
    t.index ["room_id"], name: "index_ai_room_shared_writing_preferences_on_room_id", unique: true
    t.check_constraint "lock_version >= 0", name: "shared_writing_preferences_nonnegative_lock"
  end

  create_table "ai_room_writing_preferences", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "user_id", null: false
    t.string "profile_id", limit: 24
    t.string "writing_style", limit: 48, default: "polish_clarity", null: false
    t.string "language", limit: 8, default: "auto", null: false
    t.string "tone", limit: 24, default: "neutral", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_ai_room_writing_preferences_on_room_id"
    t.index ["user_id", "room_id"], name: "index_ai_room_writing_preferences_member_scope", unique: true
    t.index ["user_id"], name: "index_ai_room_writing_preferences_on_user_id"
  end

  create_table "ai_usage_reservations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.string "request_key_hash", limit: 64, null: false
    t.string "purpose", limit: 36, null: false
    t.string "state", limit: 16, default: "reserved", null: false
    t.bigint "reserved_ticks", null: false
    t.bigint "allocated_ticks", null: false
    t.bigint "actual_ticks"
    t.date "day_utc", null: false
    t.date "month_utc", null: false
    t.datetime "uncertain_at"
    t.datetime "settled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["month_utc"], name: "index_ai_usage_reservations_global_month"
    t.index ["request_key_hash"], name: "index_ai_usage_reservations_unique_request", unique: true
    t.index ["room_id", "month_utc"], name: "index_ai_usage_reservations_room_month"
    t.index ["room_id"], name: "index_ai_usage_reservations_on_room_id"
    t.index ["user_id", "day_utc"], name: "index_ai_usage_reservations_user_day"
    t.index ["user_id", "month_utc"], name: "index_ai_usage_reservations_user_month"
    t.index ["user_id"], name: "index_ai_usage_reservations_on_user_id"
    t.check_constraint "reserved_ticks > 0 AND allocated_ticks >= 0 AND (actual_ticks IS NULL OR actual_ticks >= 0)", name: "ai_usage_reservations_nonnegative_ticks"
  end

  create_table "conversation_notification_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.boolean "muted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_conversation_notification_preferences_on_room_id"
    t.index ["user_id", "room_id"], name: "index_conversation_notification_preferences_unique", unique: true
    t.index ["user_id"], name: "index_conversation_notification_preferences_on_user_id"
  end

  create_table "conversation_read_states", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "user_id", null: false
    t.bigint "last_read_message_id", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_conversation_read_states_on_room_id"
    t.index ["user_id", "room_id"], name: "index_conversation_read_states_on_user_and_room", unique: true
    t.index ["user_id"], name: "index_conversation_read_states_on_user_id"
    t.check_constraint "last_read_message_id >= 0", name: "conversation_read_states_nonnegative_cursor"
  end

  create_table "joinables", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_id"], name: "index_joinables_on_room_id"
    t.index ["user_id", "room_id"], name: "index_joinables_on_user_and_room_unique", unique: true
    t.index ["user_id"], name: "index_joinables_on_user_id"
  end

  create_table "message_reactions", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "user_id", null: false
    t.string "emoji", limit: 16, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "user_id", "emoji"], name: "index_message_reactions_on_message_user_emoji", unique: true
    t.index ["message_id"], name: "index_message_reactions_on_message_id"
    t.index ["user_id"], name: "index_message_reactions_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "reply_to_id"
    t.boolean "ai_assisted", default: false, null: false
    t.index ["reply_to_id"], name: "index_messages_on_reply_to_id"
    t.index ["room_id", "created_at"], name: "index_messages_on_room_id_and_created_at"
    t.index ["room_id"], name: "index_messages_on_room_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.bigint "message_id", null: false
    t.string "event_key", limit: 96, null: false
    t.string "kind", limit: 32, default: "new_message", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_notifications_on_message_id"
    t.index ["room_id"], name: "index_notifications_on_room_id"
    t.index ["user_id", "event_key"], name: "index_notifications_user_event_key", unique: true
    t.index ["user_id", "read_at", "created_at"], name: "index_notifications_user_unread_recent"
    t.index ["user_id", "room_id", "message_id"], name: "index_notifications_user_room_message"
    t.index ["user_id"], name: "index_notifications_on_user_id"
    t.check_constraint "kind::text = 'new_message'::text", name: "notifications_supported_kind"
  end

  create_table "participants", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "group_role", limit: 16
    t.index ["room_id"], name: "index_participants_on_room_id"
    t.index ["user_id", "room_id"], name: "index_participants_on_user_and_room_unique", unique: true
    t.index ["user_id"], name: "index_participants_on_user_id"
    t.check_constraint "group_role IS NULL OR (group_role::text = ANY (ARRAY['owner'::character varying::text, 'member'::character varying::text]))", name: "participants_supported_group_role"
  end

  create_table "private_group_invitations", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "user_id", null: false
    t.bigint "invited_by_id", null: false
    t.string "status", limit: 16, default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_private_group_invitations_on_invited_by_id"
    t.index ["room_id", "user_id"], name: "index_group_invitations_room_user", unique: true
    t.index ["room_id"], name: "index_private_group_invitations_on_room_id"
    t.index ["user_id", "status", "created_at"], name: "index_group_invitations_inbox"
    t.index ["user_id"], name: "index_private_group_invitations_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'accepted'::character varying::text, 'declined'::character varying::text, 'revoked'::character varying::text])", name: "group_invitations_supported_status"
  end

  create_table "room_ai_instruction_revisions", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "editor_id"
    t.integer "revision_number", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["editor_id"], name: "index_room_ai_instruction_revisions_on_editor_id"
    t.index ["room_id", "revision_number"], name: "index_room_ai_instructions_unique_revision", unique: true
    t.index ["room_id"], name: "index_room_ai_instruction_revisions_on_room_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name"
    t.boolean "is_private", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_message_at"
    t.string "kind", limit: 32
    t.bigint "owner_id"
    t.index ["kind"], name: "index_rooms_on_kind"
    t.index ["name"], name: "index_rooms_on_name", unique: true
    t.check_constraint "kind IS NULL OR (kind::text = ANY (ARRAY['public_room'::character varying::text, 'direct_message'::character varying::text, 'private_group'::character varying::text]))", name: "rooms_supported_kind"
    t.check_constraint "kind::text IS DISTINCT FROM 'private_group'::text OR is_private = true AND owner_id IS NOT NULL", name: "private_group_requires_owner"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "avatar"
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0
    t.integer "role"
    t.integer "current_room"
    t.boolean "share_presence", default: true, null: false
    t.string "display_name", limit: 48
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_account_writing_preferences", "users"
  add_foreign_key "ai_conversation_goals", "rooms"
  add_foreign_key "ai_conversation_goals", "users"
  add_foreign_key "ai_deliverable_revisions", "ai_deliverables"
  add_foreign_key "ai_deliverable_revisions", "users", column: "author_id"
  add_foreign_key "ai_deliverables", "rooms"
  add_foreign_key "ai_deliverables", "users", column: "owner_id"
  add_foreign_key "ai_evidence_review_events", "messages"
  add_foreign_key "ai_evidence_review_events", "rooms"
  add_foreign_key "ai_evidence_review_events", "users", column: "reviewer_id"
  add_foreign_key "ai_personal_enablements", "users", on_delete: :cascade
  add_foreign_key "ai_room_context_consents", "rooms"
  add_foreign_key "ai_room_context_consents", "users"
  add_foreign_key "ai_room_shared_writing_preferences", "rooms", on_delete: :cascade
  add_foreign_key "ai_room_shared_writing_preferences", "users", column: "editor_id", on_delete: :nullify
  add_foreign_key "ai_room_writing_preferences", "rooms"
  add_foreign_key "ai_room_writing_preferences", "users"
  add_foreign_key "ai_usage_reservations", "rooms"
  add_foreign_key "ai_usage_reservations", "users"
  add_foreign_key "conversation_notification_preferences", "rooms", on_delete: :cascade
  add_foreign_key "conversation_notification_preferences", "users", on_delete: :cascade
  add_foreign_key "conversation_read_states", "rooms", on_delete: :cascade
  add_foreign_key "conversation_read_states", "users", on_delete: :cascade
  add_foreign_key "joinables", "rooms"
  add_foreign_key "joinables", "users"
  add_foreign_key "message_reactions", "messages", on_delete: :cascade
  add_foreign_key "message_reactions", "users", on_delete: :cascade
  add_foreign_key "messages", "messages", column: "reply_to_id", on_delete: :nullify
  add_foreign_key "messages", "rooms"
  add_foreign_key "messages", "users"
  add_foreign_key "notifications", "messages", on_delete: :cascade
  add_foreign_key "notifications", "rooms", on_delete: :cascade
  add_foreign_key "notifications", "users", on_delete: :cascade
  add_foreign_key "participants", "rooms"
  add_foreign_key "participants", "users"
  add_foreign_key "private_group_invitations", "rooms", on_delete: :cascade
  add_foreign_key "private_group_invitations", "users", column: "invited_by_id", on_delete: :cascade
  add_foreign_key "private_group_invitations", "users", on_delete: :cascade
  add_foreign_key "room_ai_instruction_revisions", "rooms"
  add_foreign_key "room_ai_instruction_revisions", "users", column: "editor_id"
  add_foreign_key "rooms", "users", column: "owner_id"
end
