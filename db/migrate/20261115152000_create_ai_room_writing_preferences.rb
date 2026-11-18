# frozen_string_literal: true

# Additive, per-user/per-room preferences. Existing messages, storage and
# context-consent tables remain untouched; no auto AI authorization exists.
class CreateAiRoomWritingPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_room_writing_preferences do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :profile_id, limit: 24
      t.string :writing_style, null: false, default: "polish_clarity", limit: 48
      t.string :language, null: false, default: "auto", limit: 8
      t.string :tone, null: false, default: "neutral", limit: 24
      t.timestamps
    end
    add_index :ai_room_writing_preferences, [:user_id, :room_id], unique: true,
      name: "index_ai_room_writing_preferences_member_scope"
  end
end
