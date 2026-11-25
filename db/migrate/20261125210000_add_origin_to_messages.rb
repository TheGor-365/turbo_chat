# frozen_string_literal: true

class AddOriginToMessages < ActiveRecord::Migration[8.1]
  def change
    # NULL explicitly means unclassified existing/legacy writer data.
    # Do not infer that a historical ai_assisted=false row was human-only.
    add_column :messages, :origin, :string, limit: 32
    add_check_constraint :messages, <<~SQL.squish, name: "messages_origin_consistent"
      origin IS NULL OR
      (origin = 'manual' AND ai_assisted = FALSE) OR
      (origin IN ('ai_edited', 'ai_generated', 'ai_assisted_legacy', 'synthetic') AND ai_assisted = TRUE)
    SQL
  end
end
