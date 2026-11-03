class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  scope :all_except, ->(user) { where.not(id: user) }

  has_many :messages
  has_one_attached :avatar
  has_many :joinables, dependent: :destroy
  has_many :joined_rooms, through: :joinables, source: :room

  after_create_commit { broadcast_append_to "users" }
  after_update_commit :broadcast_update
  after_create_commit :add_default_avatar

  enum role: %i[user admin]
  enum status: %i[offline away online]

  after_initialize :set_default_role, if: :new_record?

  def avatar_thumbnail
    avatar.attached? ? avatar.variant(resize_to_limit: [150, 150]).processed : 'default_profile.jpg'
  end

  def chat_thumbnail
    avatar.attached? ? avatar.variant(resize_to_limit: [50, 50]).processed : 'default_profile.jpg'
  end

  def nav_thumbnail
    avatar.attached? ? avatar.variant(resize_to_limit: [45, 45]).processed : 'default_profile.jpg'
  end

  def broadcast_update
    broadcast_replace_to 'user_status', partial: 'users/status', locals: { user: self }
  end

  def has_joined_room(room)
    joined_rooms.include?(room)
  end

  def status_to_css
    case status
    when 'online' then 'bg-success'
    when 'away' then 'bg-warning'
    else 'bg-dark'
    end
  end

  private

  def add_default_avatar
    return if avatar.attached?

    File.open(Rails.root.join('app', 'assets', 'images', 'default_profile.jpg'), 'rb') do |file|
      avatar.attach(io: file, filename: 'default_profile.jpg', content_type: 'image/jpeg')
    end
  end

  def set_default_role
    self.role ||= :user
  end
end
