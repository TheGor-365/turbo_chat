class MessageReaction < ApplicationRecord
  EMOJIS = %w[👍 ❤️ 😂 😮 🔥 🎉].freeze

  belongs_to :message, inverse_of: :message_reactions
  belongs_to :user

  validates :emoji, inclusion: { in: EMOJIS }
  # Duplicate reactions are constrained atomically by the database unique index.
  # Rails uniqueness validation would defeat create_or_find_by! on repeated clicks.
  validate :member_of_message_room

  # Register the same callback once for both events. Defining separate
  # after_create_commit/after_destroy_commit with the same method name can
  # override the first registration in Active Record.
  after_commit :broadcast_reaction_change, on: %i[create destroy]

  private

  def member_of_message_room
    return if user.blank? || message.blank?
    errors.add(:message, "is not accessible") unless message.room.accessible_to?(user)
  end

  def broadcast_reaction_change
    return unless message&.persisted?

    # The association may have been cached while building/destroying a
    # reaction. Every recipient must see the newly committed DB state.
    # Message sync compares Message#updated_at. Without advancing that version,
    # reaction-only changes are missed on HTTP recovery after a socket outage.
    # touch is monotonic for both additions and removals; no migration needed.
    message.touch
    message.message_reactions.reset
    message.broadcast_reactions_changed
  end
end
