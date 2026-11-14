class AddDisplayNameToUsers < ActiveRecord::Migration[8.1]
  def change
    # Existing users remain anonymous; never backfill a private login email.
    add_column :users, :display_name, :string, limit: 48
  end
end
