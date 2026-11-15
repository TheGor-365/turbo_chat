# frozen_string_literal: true

# Append-only, participant-visible room instruction revisions. These are
# untrusted user-authored data, not a system prompt, API key, authorization,
# context consent, provider spend approval or an instruction to send messages.
class RoomAiInstructionRevision < ApplicationRecord
  MAX_CHARS = 4_000
  MAX_BYTES = 16_000
  INVALID_CONTROLS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u202A-\u202E\u2066-\u2069]/.freeze

  belongs_to :room
  belongs_to :editor, class_name: "User", inverse_of: :edited_room_ai_instruction_revisions, optional: true

  validates :revision_number, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :room_id }
  validates :content, length: { maximum: MAX_CHARS }
  validate :content_is_safe_text
  validate :room_is_private
  validate :author_can_edit_room

  before_validation :canonicalize_text

  def self.can_edit?(room:, user:)
    return false unless room&.is_private? && room.accessible_to?(user)
    room.direct_message? || room.owned_by?(user)
  end

  def public_snapshot
    { revision_number: revision_number, content: content,
      editor: editor&.chat_label || "Former member", updated_at: created_at.iso8601 }
  end

  private

  def canonicalize_text
    self.content = content.gsub("\r\n", "\n").strip if content.is_a?(String)
  end

  def content_is_safe_text
    return errors.add(:content, :invalid) unless content.is_a?(String)
    errors.add(:content, "exceeds byte limit") if content.bytesize > MAX_BYTES
    errors.add(:content, "contains unsupported control characters") if
      content.match?(INVALID_CONTROLS)
  end

  def room_is_private
    errors.add(:room, :invalid) unless room&.is_private?
  end

  def author_can_edit_room
    return unless new_record?
    errors.add(:editor, :invalid) unless self.class.can_edit?(room: room, user: editor)
  end
end
