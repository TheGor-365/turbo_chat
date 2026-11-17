# frozen_string_literal: true

# One explicit personal action tied to the exact version of a source message.
# A review event is not a room decision, a contract, or a participant quorum.
# Stale versions are never treated as current review/approval.
class AiEvidenceReviewEvent < ApplicationRecord
  STANCES = %w[acknowledged disputed withdrawn].freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  belongs_to :room
  belongs_to :message
  belongs_to :reviewer, class_name: "User"

  validates :stance, inclusion: { in: STANCES }
  validates :source_version_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :request_key, format: { with: UUID },
    uniqueness: { scope: :reviewer_id }
  validate :source_belongs_to_room
  validate :reviewer_is_current_member

  # All state transitions create NEW events. Destruction only occurs through
  # explicit privacy cleanup or source/room/account cascading deletion.
  def readonly?
    persisted?
  end

  private

  def source_belongs_to_room
    errors.add(:message, "must belong to this room") if
      room && message && message.room_id != room.id
  end

  def reviewer_is_current_member
    errors.add(:reviewer, "must be a current participant") if
      room && reviewer && !room.accessible_to?(reviewer)
  end
end
