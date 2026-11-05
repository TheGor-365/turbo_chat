# One user can mute a conversation without altering unread message cursors,
# membership, stream delivery or the other member's preferences.
class ConversationNotificationPreference < ApplicationRecord
  belongs_to :user
  belongs_to :room

  validates :user_id, uniqueness: { scope: :room_id }

  def self.muted_for?(user, room)
    return false unless user && room

    where(user_id: user.id, room_id: room.id, muted: true).exists?
  end
end
