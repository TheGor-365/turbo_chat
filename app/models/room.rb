class Room < ApplicationRecord
  validates_uniqueness_of :name

  scope :public_rooms, -> { where(is_private: false) }
  after_update_commit { broadcast_if_public }

  has_many :messages
  has_many :participants, dependent: :destroy
  has_many :joinables, dependent: :destroy
  has_many :joined_users, through: :joinables, source: :user

  def accessible_to?(user)
    return false unless user
    is_private? ? participants.exists?(user_id: user.id) : joinables.exists?(user_id: user.id)
  end

  def broadcast_if_public
    return if is_private?

    broadcast_latest_message
  end

  def self.create_private_room(users, room_name)
    single_room = Room.find_or_create_by!(name: room_name) { |room| room.is_private = true }
    raise ActiveRecord::RecordInvalid, single_room unless single_room.is_private?

    users.each do |user|
      single_room.participants.find_or_create_by!(user: user)
    end

    single_room
  end

  def participant?(room, user)
    room.participants.where(user: user).exists?
  end

  def latest_message
    messages.includes(:user).order(created_at: :desc).first
  end

  def broadcast_latest_message
    last_message = latest_message

    return unless last_message

    target = "room_#{id} last_message"

    broadcast_replace_to(
      'rooms',
      target: target,
      partial: 'rooms/last_message',
      locals: { room: self, user: last_message.user, last_message: last_message }
    )
  end
end
