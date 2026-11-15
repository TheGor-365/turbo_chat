# frozen_string_literal: true

# Additive, auditable per-room instructions. No text or attachment migration.
class CreateRoomAiInstructionRevisions < ActiveRecord::Migration[8.0]
  def change
    create_table :room_ai_instruction_revisions do |t|
      t.references :room, null: false, foreign_key: true
      t.references :editor, null: false, foreign_key: { to_table: :users }
      t.integer :revision_number, null: false
      t.text :content, null: false
      t.timestamps
    end

    add_index :room_ai_instruction_revisions, [:room_id, :revision_number],
      unique: true, name: "index_room_ai_instructions_unique_revision"
  end
end
