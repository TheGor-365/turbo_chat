class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :room
  belongs_to :message

  KINDS = %w[new_message].freeze
  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  validates :event_key, presence: true, length: { maximum: 96 }
  validates :kind, inclusion: { in: KINDS }
  validate :message_matches_room
  validate :recipient_is_not_author, on: :create

  # This is a separate persistent event feed, NOT an alternative read cursor.
  # The current room's ConversationReadState remains the source of truth for
  # conversation unread badges and marks these events read in one batch.
  def self.record_message!(message, recipient)
    return if message.user_id == recipient.id
    return if ConversationNotificationPreference.muted_for?(recipient, message.room)

    create_or_find_by!(user: recipient, message: message, room: message.room,
      event_key: "message:#{message.id}", kind: "new_message")
  end

  # Keep visibility rooted in actual, current room membership, even when a
  # user once received a notification and later lost access to the room.
  def self.visible_to(user)
    return none unless user

    private_rooms = Room.joins(:participants).where(is_private: true, participants: { user_id: user.id }).select(:id)
    public_rooms = Room.joins(:joinables).where(is_private: false, joinables: { user_id: user.id }).select(:id)
    where(user_id: user.id, room_id: private_rooms).or(where(user_id: user.id, room_id: public_rooms))
  end

  def mark_read!
    update_column(:read_at, Time.current) if read_at.nil?
  end

  private

  def message_matches_room
    errors.add(:message, "must belong to this conversation") if message && room && message.room_id != room.id
  end

  def recipient_is_not_author
    errors.add(:user, "cannot be the message author") if user && message && user.id == message.user_id
  end
end
