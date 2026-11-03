class Room < ApplicationRecord
  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { case_sensitive: false }
  validate :reserve_private_room_names

  scope :public_rooms, -> { where(is_private: false) }

  has_many :messages, dependent: :destroy
  has_many :participants, dependent: :destroy
  has_many :joinables, dependent: :destroy
  has_many :joined_users, through: :joinables, source: :user

  after_update_commit :broadcast_if_public

  def accessible_to?(user)
    return false unless user

    if is_private?
      participants.exists?(user_id: user.id)
    else
      joinables.exists?(user_id: user.id)
    end
  end

  def self.create_private_room(users, room_name)
    ids = users.map(&:id).uniq
    raise ArgumentError, 'A direct message requires two different users' unless ids.length == 2

    room = create_or_find_by!(name: room_name) { |new_room| new_room.is_private = true }
    raise ActiveRecord::RecordNotFound unless room.is_private?

    ids.each { |id| Participant.create_or_find_by!(user_id: id, room_id: room.id) }
    room
  end

  def participant?(room, user)
    room.participants.exists?(user_id: user.id)
  end

  def latest_message
    messages.includes(:user).order(created_at: :desc).first
  end

  def broadcast_if_public
    return if is_private?
    broadcast_latest_message
  end

  def broadcast_latest_message
    last_message = latest_message
    return unless last_message

    broadcast_replace_to(
      'rooms',
      target: "room_#{id} last_message",
      partial: 'rooms/last_message',
      locals: { room: self, user: last_message.user, last_message: last_message }
    )
  end

  private

  def reserve_private_room_names
    return if is_private?

    errors.add(:name, 'is reserved') if name.to_s.match?(/\A(?:private_|dm_)/i)
  end
end
