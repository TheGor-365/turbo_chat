# frozen_string_literal: true

class AddAiAssistedToMessages < ActiveRecord::Migration[8.1]
  def change
    # Additive and non-destructive. Existing messages remain human-only.
    add_column :messages, :ai_assisted, :boolean, null: false, default: false
  end
end
