# frozen_string_literal: true

require "digest"
require "json"

# Permission for background processing of one member's room messages. Consent
# is bound to the exact current membership rows, not just the user ID set.
# No model preference and no one-click generator can grant this implicitly.
class AiRoomAutomationConsent < ApplicationRecord
  SHA = /\A[0-9a-f]{64}\z/

  belongs_to :room
  belongs_to :user

  validates :user_id, uniqueness: { scope: :room_id }
  validates :member_set_fingerprint, format: { with: SHA }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :background_context_enabled, :unattended_send_enabled,
    :scheduled_outcomes_enabled, inclusion: { in: [true, false] }
  validate :scoped_automation_permissions

  def self.fingerprint_for(room)
    memberships = room.participants.order(:user_id, :id).pluck(:id, :user_id)
    Digest::SHA256.hexdigest(JSON.generate(memberships))
  end

  def current_for?(room)
    room_id == room.id && member_set_fingerprint == self.class.fingerprint_for(room)
  end

  def public_snapshot(room:)
    { background_context_enabled: background_context_enabled,
      unattended_send_enabled: unattended_send_enabled,
      scheduled_outcomes_enabled: scheduled_outcomes_enabled,
      current_membership: current_for?(room), revision: revision }
  end

  private

  def scoped_automation_permissions
    if (unattended_send_enabled || scheduled_outcomes_enabled) && !background_context_enabled
      errors.add(:background_context_enabled, "required for background automation")
    end
    if room && user && (!room.is_private? || !room.accessible_to?(user))
      errors.add(:base, "Only current private-room members can consent")
    end
  end
end
