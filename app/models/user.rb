class User < ApplicationRecord

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  scope :all_except, ->(user) { where.not(id: user) }
  after_create_commit { broadcast_append_to "users" }

  has_many :messages
  has_one_attached :avatar

  after_commit :add_default_avatar, on: %i[ create update ]
  after_update_commit { broadcast_update }

  enum status: %i[ offline away online ]

  def avatar_thumbnail
    avatar.variant(resize_to_limit: [150, 150]).processed
  end

  def chat_thumbnail
    avatar.variant(resize_to_limit: [50, 50]).processed
  end

  def nav_thumbnail
    avatar.variant(resize_to_limit: [45, 45]).processed
  end

  def broadcast_update
    broadcast_append_to 'user_status', partial: 'users/status', user: self
  end

  def status_to_css
    case status
    when 'online'
      'bg-success'
    when 'away'
      'bg-warning'
    when 'offline'
      'bg-dark'
    else
      'bg-dark'
    end
  end

  private

  def add_default_avatar
    return if avatar.attached?

    avatar.attach(
      io: File.open(Rails.root.join('app', 'assets', 'images', 'defautl_profile.jpg')),
      filename: 'defautl_profile.jpg',
      content_type: 'image/jpg'
    )
  end
end
