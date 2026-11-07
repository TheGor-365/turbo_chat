class AddReplyToMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :reply_to, index: true, null: true,
      foreign_key: { to_table: :messages, on_delete: :nullify }
  end
end
