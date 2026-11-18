# frozen_string_literal: true

# Personal configuration only. This migration does not enable background
# generation, paid provider access, automatic Send or document schedules.
class CreateAiAutomationPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_automation_policies do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :reply_mode, null: false, default: "off", limit: 20
      t.string :summary_mode, null: false, default: "off", limit: 24
      t.string :summary_kind, null: false, default: "conversation_summary", limit: 32
      t.integer :summary_after_messages, null: false, default: 20
      t.integer :reply_delay_seconds, null: false, default: 30
      t.integer :revision, null: false, default: 1
      t.timestamps
    end
    add_index :ai_automation_policies, %i[room_id user_id], unique: true,
      name: "index_ai_automation_policies_per_member_room"
  end
end
