class Message < ApplicationRecord
  MAX_BODY_LENGTH = 5_000
  MAX_ATTACHMENTS = 5
  MAX_ATTACHMENT_BYTES = 5.megabytes
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp application/pdf text/plain text/markdown audio/webm video/webm].freeze

  belongs_to :user
  belongs_to :room
  belongs_to :reply_to, class_name: "Message", optional: true
  has_many :replies, class_name: "Message", foreign_key: :reply_to_id, dependent: :nullify, inverse_of: :reply_to
  has_many_attached :attachments, dependent: :destroy

  validate :body_or_attachments_present
  validates :body, length: { maximum: MAX_BODY_LENGTH }
  validate :attachment_constraints
  validate :author_is_room_member
  validate :reply_stays_in_room

  after_create_commit do
    update_parent_room
    broadcast_recipients.each do |recipient|
      broadcast_append_to [room, recipient],
        target: "messages-container",
        partial: "messages/message",
        locals: { message: self, viewer: recipient }
    end
  end

  after_update_commit :broadcast_updated_message, if: :saved_change_to_body?
  after_destroy_commit :broadcast_removed_message

  def chat_attachment(index)
    return unless attachments.attached?

    attachment = attachments[index]
    return unless attachment
    return attachment.variant(resize_to_limit: [150, 150]).processed if attachment.image?

    attachment
  end

  def update_parent_room
    room.update(last_message_at: Time.current)
  end

  private

  def broadcast_recipients
    users = if room.is_private?
      room.participants.includes(:user).map(&:user)
    else
      room.joined_users.to_a
    end
    users.uniq
  end

  def broadcast_updated_message
    broadcast_recipients.each do |recipient|
      broadcast_replace_to [room, recipient],
        target: "message_#{id}",
        partial: "messages/message",
        locals: { message: self, viewer: recipient }
    end
  end

  def broadcast_removed_message
    broadcast_recipients.each do |recipient|
      broadcast_remove_to [room, recipient], target: "message_#{id}"
    end
  end

  def body_or_attachments_present
    errors.add(:base, "Message cannot be blank") if body.blank? && attachments.blank?
  end

  def author_is_room_member
    return if user.blank? || room.blank?
    errors.add(:room, "is not accessible") unless room.accessible_to?(user)
  end

  def reply_stays_in_room
    return if reply_to_id.blank?

    if reply_to.nil? || reply_to.room_id != room_id || (persisted? && reply_to_id == id)
      errors.add(:reply_to, "must refer to a message in the same conversation")
    end
  end

  def attachment_constraints
    return if attachments.blank?

    errors.add(:attachments, "too many files") if attachments.size > MAX_ATTACHMENTS
    attachments.each do |attachment|
      blob = attachment.blob
      next unless blob

      errors.add(:attachments, "file exceeds 5 MB") if blob.byte_size > MAX_ATTACHMENT_BYTES
      errors.add(:attachments, "type is not allowed") unless ALLOWED_CONTENT_TYPES.include?(blob.content_type)
    end
  end
end
