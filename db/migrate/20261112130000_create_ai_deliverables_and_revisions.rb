# frozen_string_literal: true

class CreateAiDeliverablesAndRevisions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_deliverables do |t|
      t.references :room, null: false, foreign_key: true
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :kind, null: false, limit: 40
      t.string :state, null: false, default: "draft", limit: 24
      t.timestamps
    end
    add_index :ai_deliverables, [:room_id, :owner_id, :created_at],
      name: "index_ai_deliverables_room_owner_created"

    create_table :ai_deliverable_revisions do |t|
      t.references :ai_deliverable, null: false, foreign_key: true, index: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.integer :version, null: false
      t.text :body_markdown, null: false
      t.jsonb :source_message_ids, null: false, default: []
      t.string :body_sha256, null: false, limit: 64
      t.timestamps
    end
    add_index :ai_deliverable_revisions, [:ai_deliverable_id, :version],
      unique: true, name: "index_ai_deliverable_revisions_unique_version"
  end
end
