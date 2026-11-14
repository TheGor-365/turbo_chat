class CreateConversationReadStates < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_read_states do |t|
      t.references :room, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # Cursor is deliberately not a foreign key: deleting a message must
      # never make previously read messages appear unread again.
      t.bigint :last_read_message_id, default: 0, null: false
      t.timestamps
    end

    add_index :conversation_read_states, %i[user_id room_id],
      unique: true, name: "index_conversation_read_states_on_user_and_room"
    add_check_constraint :conversation_read_states, "last_read_message_id >= 0",
      name: "conversation_read_states_nonnegative_cursor"
  end
end
