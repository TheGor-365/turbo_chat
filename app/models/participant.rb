class Participant < ApplicationRecord
  belongs_to :user
  belongs_to :room

  validates :group_role, inclusion: { in: %w[owner member] },
    if: -> { room&.private_group? }
  validate :owner_role_matches_room

  private

  def owner_role_matches_room
    return unless room&.private_group?

    if user_id == room.owner_id && group_role != "owner"
      errors.add(:group_role, "must be owner for the group creator")
    elsif user_id != room.owner_id && group_role == "owner"
      errors.add(:group_role, "is reserved for the group creator")
    end
  end
end
