class MessageReaction < ApplicationRecord
  EMOJIS = %w[👍 ❤️ 😂 😮 🔥 🎉].freeze

  belongs_to :message, inverse_of: :message_reactions
  belongs_to :user

  validates :emoji, inclusion: { in: EMOJIS }
  # Duplicate reactions are constrained atomically by the database unique index.
  # Rails uniqueness validation would defeat create_or_find_by! on repeated clicks.
  validate :member_of_message_room

  after_create_commit :broadcast_reaction_change
  after_destroy_commit :broadcast_reaction_change

  private

  def member_of_message_room
    return if user.blank? || message.blank?
    errors.add(:message, "is not accessible") unless message.room.accessible_to?(user)
  end

  def broadcast_reaction_change
    message.broadcast_reactions_changed if message&.persisted?
  end
end
