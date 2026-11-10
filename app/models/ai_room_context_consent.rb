# frozen_string_literal: true

# An explicit, revocable permission to use this author's messages (including
# earlier messages in the room) in manual requests to the xAI API. This record
# is intentionally separate from notifications, presence, and read receipts.
class AiRoomContextConsent < ApplicationRecord
  belongs_to :room
  belongs_to :user

  validates :user_id, uniqueness: { scope: :room_id }
  validate :member_can_grant, if: -> { granted_at.present? }

  def enabled?
    granted_at.present? && revoked_at.nil?
  end

  def grant!
    raise ArgumentError, "Not an eligible private conversation" unless eligible_member?
    update!(granted_at: Time.current, revoked_at: nil)
  end

  def revoke!
    update!(granted_at: nil, revoked_at: Time.current)
  end

  def self.enabled_for?(room:, user:)
    return false unless room && user && room.is_private? && room.accessible_to?(user)
    where(room_id: room.id, user_id: user.id, revoked_at: nil)
      .where.not(granted_at: nil).exists?
  end

  private

  def eligible_member?
    room&.is_private? && room.accessible_to?(user)
  end

  def member_can_grant
    errors.add(:base, "Only a member may authorize their own room context") unless eligible_member?
  end
end
