class CreateConversationNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_notification_preferences do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :room, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :muted, null: false, default: false
      t.timestamps
    end

    add_index :conversation_notification_preferences, %i[user_id room_id],
      unique: true, name: "index_conversation_notification_preferences_unique"
  end
end
