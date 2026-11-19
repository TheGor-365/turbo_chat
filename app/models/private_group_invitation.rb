class PrivateGroupInvitation < ApplicationRecord
  STATUSES = %w[pending accepted declined revoked].freeze

  belongs_to :room
  belongs_to :user
  belongs_to :invited_by, class_name: "User"

  scope :pending, -> { where(status: "pending") }

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :room_id }
  validate :room_is_private_group
  validate :inviter_is_owner

  private

  def room_is_private_group
    errors.add(:room, "must be a private group") unless room&.private_group?
  end

  def inviter_is_owner
    errors.add(:invited_by, "must own the group") unless room&.owned_by?(invited_by)
  end
end
