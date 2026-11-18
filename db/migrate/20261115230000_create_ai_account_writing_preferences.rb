# frozen_string_literal: true

# Additive only: preserves locally modified db/schema.rb, all messages,
# storage, account grants and room overrides.
class CreateAiAccountWritingPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_account_writing_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :profile_id, limit: 24
      t.string :writing_style, null: false, default: "polish_clarity", limit: 48
      t.string :language, null: false, default: "auto", limit: 8
      t.string :tone, null: false, default: "neutral", limit: 24
      t.timestamps
    end
  end
end
