# frozen_string_literal: true

# Durable metadata journal only; no background jobs, provider calls, or Send.
# Never store raw incoming message text or generated output in this registry.
class CreateAiAutomationRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_automation_runs do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :ai_automation_policy, null: false, foreign_key: true
      t.references :trigger_message, null: true,
        foreign_key: { to_table: :messages, on_delete: :nullify }
      t.string :run_kind, null: false, limit: 32
      t.string :event_key, null: false, limit: 64
      t.string :source_fingerprint, null: false, limit: 64
      t.jsonb :source_message_ids, null: false, default: []
      t.integer :policy_revision, null: false
      t.integer :goal_revision
      t.string :status, null: false, default: "recorded", limit: 16
      t.string :cancellation_reason, limit: 64
      t.datetime :canceled_at
      t.timestamps
    end

    add_index :ai_automation_runs, :event_key, unique: true,
      name: "index_ai_automation_runs_unique_event_key"
    add_index :ai_automation_runs, [:room_id, :user_id, :status, :created_at],
      name: "index_ai_automation_runs_room_member_status"
  end
end
