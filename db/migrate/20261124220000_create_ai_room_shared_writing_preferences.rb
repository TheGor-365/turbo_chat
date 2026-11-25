class CreateAiRoomSharedWritingPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_room_shared_writing_preferences do |t|
      t.references :room, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :editor, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :profile_id, limit: 24
      t.string :writing_style, limit: 48, null: false
      t.string :language, limit: 8, null: false
      t.string :tone, limit: 24, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.check_constraint "lock_version >= 0", name: "shared_writing_preferences_nonnegative_lock"
    end
  end
end
