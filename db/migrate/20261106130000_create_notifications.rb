class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :room, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.string :event_key, null: false, limit: 96
      t.string :kind, null: false, default: "new_message", limit: 32
      t.datetime :read_at
      t.timestamps
    end

    add_index :notifications, %i[user_id event_key], unique: true,
      name: "index_notifications_user_event_key"
    add_index :notifications, %i[user_id read_at created_at],
      name: "index_notifications_user_unread_recent"
    add_index :notifications, %i[user_id room_id message_id],
      name: "index_notifications_user_room_message"
    add_check_constraint :notifications, "kind IN ('new_message')",
      name: "notifications_supported_kind"
  end
end
