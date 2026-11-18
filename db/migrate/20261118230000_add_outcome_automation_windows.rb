# frozen_string_literal: true

# Immutable source windows, and per-person progress for after-N reports.
class AddOutcomeAutomationWindows < ActiveRecord::Migration[8.0]
  def change
    change_table :ai_automation_runs do |t|
      t.bigint :source_after_message_id
      t.bigint :source_through_message_id
      t.date :source_utc_day
    end

    create_table :ai_outcome_schedule_cursors do |t|
      t.references :ai_automation_policy, null: false, foreign_key: true
      t.bigint :last_message_id, null: false, default: 0
      t.integer :policy_revision, null: false
      t.timestamps
    end
    add_index :ai_outcome_schedule_cursors, :ai_automation_policy_id,
      unique: true, name: "index_ai_outcome_schedule_cursors_unique_policy"
    add_check_constraint :ai_outcome_schedule_cursors, "last_message_id >= 0",
      name: "ai_outcome_cursor_positive"
  end
end
