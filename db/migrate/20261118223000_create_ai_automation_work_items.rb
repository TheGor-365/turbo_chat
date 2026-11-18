# frozen_string_literal: true

# Postgres durable work items for LOCAL, deterministic outcome documents only.
# No ActiveJob async adapter, paid provider, automatic chat Send or scheduler.
class CreateAiAutomationWorkItems < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_automation_work_items do |t|
      t.references :ai_automation_run, null: false, foreign_key: true
      t.references :ai_deliverable, foreign_key: true
      t.string :state, null: false, default: "queued", limit: 20
      t.integer :attempts, null: false, default: 0
      t.string :lease_token, limit: 64
      t.datetime :lease_until
      t.string :failure_code, limit: 64
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ai_automation_work_items, :ai_automation_run_id, unique: true,
      name: "index_ai_automation_work_items_unique_run"
    add_index :ai_automation_work_items, [:state, :lease_until, :id],
      name: "index_ai_automation_work_items_claim"
  end
end
