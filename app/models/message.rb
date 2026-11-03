class Message < ApplicationRecord
  MAX_BODY_LENGTH = 4_000
  MAX_ATTACHMENTS = 3
  MAX_ATTACHMENT_BYTES = 10.megabytes
  ALLOWED_ATTACHMENT_TYPES = %w[image/jpeg image/png image/webp application/pdf text/plain].freeze

  belongs_to :user
  belongs_to :room
  has_many_attached :attachments, dependent: :destroy

  validates :body, length: { maximum: MAX_BODY_LENGTH }
  validate :has_content
  validate :sender_is_member
  validate :attachment_limits

  after_create_commit do
    update_parent_room
    broadcast_append_to room
  end

  def chat_attachment(index)
    attachment = attachments[index]
    return unless attachment&.image?

    attachment.variant(resize_to_limit: [150, 150]).processed
  end

  private

  def has_content
    errors.add(:base, 'Message cannot be empty') if body.blank? && attachments.blank?
  end

  def sender_is_member
    errors.add(:base, 'Sender is not a room member') unless room&.accessible_to?(user)
  end

  def attachment_limits
    return unless attachments.attached?

    errors.add(:attachments, 'exceeds the file count limit') if attachments.size > MAX_ATTACHMENTS
    attachments.each do |attachment|
      errors.add(:attachments, 'contains an unsupported file type') unless ALLOWED_ATTACHMENT_TYPES.include?(attachment.blob.content_type)
      errors.add(:attachments, 'contains a file larger than 10 MB') if attachment.blob.byte_size > MAX_ATTACHMENT_BYTES
    end
  end

  def update_parent_room
    room.update!(last_message_at: Time.current)
  end
end
