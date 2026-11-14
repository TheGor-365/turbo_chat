class CreateMessageReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :message_reactions do |t|
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :emoji, null: false, limit: 16
      t.timestamps
    end

    add_index :message_reactions, %i[message_id user_id emoji],
      unique: true, name: "index_message_reactions_on_message_user_emoji"
  end
end
