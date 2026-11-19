# One user can mute a conversation without altering unread message cursors,
# membership, stream delivery or the other member's preferences.
class ConversationNotificationPreference < ApplicationRecord
  belongs_to :user
  belongs_to :room

  # The database unique index is authoritative. Model-level uniqueness
  # validation would prevent create_or_find_by! from rescuing a competing
  # insert and finding an existing row on repeated mute/unmute.
  def self.muted_for?(user, room)
    return false unless user && room

    where(user_id: user.id, room_id: room.id, muted: true).exists?
  end
end
