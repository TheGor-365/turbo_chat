class ConversationReadState < ApplicationRecord
  belongs_to :room
  belongs_to :user

  # Uniqueness is enforced by the composite DB index. A model-level
  # uniqueness validation would prevent create_or_find_by! from rescuing
  # a concurrent insert or finding an already-existing row.
  validates :last_read_message_id,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :reader_has_access, on: :create

  # Conditional SQL UPDATE protects against a stale tab moving a read
  # cursor backwards. Callers must first authorize the room and resolve
  # an actual message belonging to it.
  def advance_to!(message)
    raise ArgumentError, "Message belongs to a different conversation" unless message.room_id == room_id && message.persisted?

    self.class.where(id: id)
      .where("last_read_message_id < ?", message.id)
      .update_all(last_read_message_id: message.id, updated_at: Time.current)
    reload
  end

  private

  def reader_has_access
    return if room&.accessible_to?(user)

    errors.add(:room, "is not accessible")
  end
end
