class AddChatIntegrityConstraints < ActiveRecord::Migration[7.0]
  def up
    if duplicate_pairs?("joinables") || duplicate_pairs?("participants")
      raise ActiveRecord::MigrationError, "Duplicate room memberships detected; resolve manually before adding unique indexes"
    end

    if select_value("SELECT COUNT(*) - COUNT(DISTINCT name) FROM rooms WHERE name IS NOT NULL").to_i.positive?
      raise ActiveRecord::MigrationError, "Duplicate room names detected; resolve manually before applying unique index"
    end

    add_index :joinables, [:user_id, :room_id], unique: true, name: "index_joinables_on_user_and_room_unique"
    add_index :participants, [:user_id, :room_id], unique: true, name: "index_participants_on_user_and_room_unique"
    add_index :rooms, :name, unique: true
    add_index :messages, [:room_id, :created_at]
  end

  def down
    remove_index :messages, column: [:room_id, :created_at]
    remove_index :rooms, column: :name
    remove_index :participants, name: "index_participants_on_user_and_room_unique"
    remove_index :joinables, name: "index_joinables_on_user_and_room_unique"
  end

  private

  def duplicate_pairs?(table)
    select_value("SELECT COUNT(*) FROM (SELECT 1 FROM #{table} GROUP BY user_id, room_id HAVING COUNT(*) > 1) duplicates").to_i.positive?
  end
end
