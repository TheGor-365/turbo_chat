class EnforceChatUniqueness < ActiveRecord::Migration[7.0]
  def up
    # Fail closed: never silently delete or merge existing user conversations.
    {
      rooms: "SELECT LOWER(name) AS key FROM rooms WHERE name IS NOT NULL GROUP BY LOWER(name) HAVING COUNT(*) > 1 LIMIT 1",
      joinables: "SELECT room_id, user_id FROM joinables GROUP BY room_id, user_id HAVING COUNT(*) > 1 LIMIT 1",
      participants: "SELECT room_id, user_id FROM participants GROUP BY room_id, user_id HAVING COUNT(*) > 1 LIMIT 1"
    }.each do |table, query|
      raise ActiveRecord::MigrationError, "Duplicate #{table} found; inspect and resolve before migration" if execute(query).any?
    end

    add_index :rooms, "LOWER(name)", unique: true, name: "index_rooms_on_lower_name"
    add_index :joinables, %i[room_id user_id], unique: true, name: "index_joinables_on_room_and_user"
    add_index :participants, %i[room_id user_id], unique: true, name: "index_participants_on_room_and_user"
    add_index :messages, %i[room_id created_at], name: "index_messages_on_room_and_created"
  end

  def down
    remove_index :messages, name: "index_messages_on_room_and_created"
    remove_index :participants, name: "index_participants_on_room_and_user"
    remove_index :joinables, name: "index_joinables_on_room_and_user"
    remove_index :rooms, name: "index_rooms_on_lower_name"
  end
end
