# frozen_string_literal: true

# Per-member, per-room goal. Independent of shared room instructions, provider
# access and member consent. Never copy local user data into db/schema.rb by hand.
class CreateAiConversationGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_conversation_goals do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :purpose, null: false, limit: 500
      t.text :constraints
      t.string :desired_outcome, limit: 500
      t.integer :revision, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :ai_conversation_goals, %i[room_id user_id], unique: true,
      name: "index_ai_conversation_goals_personal_room_scope"
  end
end
