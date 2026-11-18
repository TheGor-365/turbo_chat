# frozen_string_literal: true

# Explicit, per-member background processing permissions. These are separate
# from the room's existing manual xAI context consents and all AI preferences.
class CreateAiRoomAutomationConsents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_room_automation_consents do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :background_context_enabled, null: false, default: false
      t.boolean :unattended_send_enabled, null: false, default: false
      t.boolean :scheduled_outcomes_enabled, null: false, default: false
      t.string :member_set_fingerprint, null: false, limit: 64
      t.integer :revision, null: false, default: 1
      t.timestamps
    end
    add_index :ai_room_automation_consents, %i[room_id user_id], unique: true,
      name: "index_ai_room_automation_consents_room_member"
  end
end
