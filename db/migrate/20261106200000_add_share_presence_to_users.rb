class AddSharePresenceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :share_presence, :boolean, null: false, default: true
  end
end
