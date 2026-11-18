# frozen_string_literal: true

# S7-A: private proposal state. Nothing here is a sent message or proof
# that a production AI provider was called.
class CreateAiReplyProposals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_reply_proposals do |t|
      t.references :ai_automation_run, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :origin, null: false, default: "offline_template", limit: 32
      t.string :state, null: false, default: "pending", limit: 16
      t.text :body, null: false
      t.string :body_sha256, null: false, limit: 64
      t.datetime :applied_at
      t.datetime :dismissed_at
      t.timestamps
    end
    add_index :ai_reply_proposals, :ai_automation_run_id, unique: true,
      name: "index_ai_reply_proposals_unique_event"
    add_index :ai_reply_proposals, [:room_id, :user_id, :created_at],
      name: "index_ai_reply_proposals_owner_recent"
    add_check_constraint :ai_reply_proposals, "char_length(body) BETWEEN 1 AND 5000",
      name: "ai_reply_proposals_body_size"
  end
end
