# frozen_string_literal: true

# Consent is per member and room, not a global profile checkbox. A user may
# revoke at any time. Never treat ordinary room membership as AI permission.
class CreateAiRoomContextConsents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_room_context_consents do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :granted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :ai_room_context_consents, [:room_id, :user_id],
      unique: true, name: "index_ai_room_context_consents_unique_member"
  end
end
