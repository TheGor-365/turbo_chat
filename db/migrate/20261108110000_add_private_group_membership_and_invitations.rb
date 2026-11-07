class AddPrivateGroupMembershipAndInvitations < ActiveRecord::Migration[8.1]
  def up
    # Additive only: preserve every legacy Room, Participant and Message. A
    # nullable kind keeps older code/test fixtures compatible during rollout.
    add_column :rooms, :kind, :string, limit: 32
    add_column :rooms, :owner_id, :bigint
    add_foreign_key :rooms, :users, column: :owner_id
    add_index :rooms, :kind

    execute <<~SQL.squish
      UPDATE rooms
         SET kind = CASE WHEN is_private THEN 'direct_message' ELSE 'public_room' END
       WHERE kind IS NULL
    SQL
    add_check_constraint :rooms,
      "kind IS NULL OR kind IN ('public_room', 'direct_message', 'private_group')",
      name: "rooms_supported_kind"
    add_check_constraint :rooms,
      "(kind IS DISTINCT FROM 'private_group') OR (is_private = TRUE AND owner_id IS NOT NULL)",
      name: "private_group_requires_owner"

    add_column :participants, :group_role, :string, limit: 16
    add_check_constraint :participants,
      "group_role IS NULL OR group_role IN ('owner', 'member')",
      name: "participants_supported_group_role"

    create_table :private_group_invitations do |t|
      t.references :room, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :invited_by, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.string :status, null: false, default: "pending", limit: 16
      t.timestamps
    end
    add_index :private_group_invitations, [:room_id, :user_id],
      unique: true, name: "index_group_invitations_room_user"
    add_index :private_group_invitations, [:user_id, :status, :created_at],
      name: "index_group_invitations_inbox"
    add_check_constraint :private_group_invitations,
      "status IN ('pending', 'accepted', 'declined', 'revoked')",
      name: "group_invitations_supported_status"
  end

  def down
    drop_table :private_group_invitations
    remove_check_constraint :participants, name: "participants_supported_group_role"
    remove_column :participants, :group_role
    remove_check_constraint :rooms, name: "private_group_requires_owner"
    remove_check_constraint :rooms, name: "rooms_supported_kind"
    remove_index :rooms, :kind
    remove_foreign_key :rooms, column: :owner_id
    remove_column :rooms, :owner_id
    remove_column :rooms, :kind
  end
end
