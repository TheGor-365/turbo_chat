class Message < ApplicationRecord
  MAX_BODY_LENGTH = 5_000
  MAX_ATTACHMENTS = 5
  MAX_ATTACHMENT_BYTES = 5.megabytes
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp application/pdf text/plain].freeze

  belongs_to :user
  belongs_to :room
  has_many_attached :attachments, dependent: :destroy

  validate :body_or_attachments_present
  validates :body, length: { maximum: MAX_BODY_LENGTH }
  validate :attachment_constraints
  validate :author_is_room_member

  after_create_commit do
    update_parent_room
    broadcast_append_to room
  end

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

  def body_or_attachments_present
    errors.add(:base, "Message cannot be blank") if body.blank? && attachments.blank?
  end

  def author_is_room_member
    return if user.blank? || room.blank?
    errors.add(:room, "is not accessible") unless room.accessible_to?(user)
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
