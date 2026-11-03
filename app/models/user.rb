class User < ApplicationRecord

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  scope :all_except, ->(user) { where.not(id: user) }

  has_many :messages
  has_one_attached :avatar
  validate :avatar_constraints
  has_many :joinables, dependent: :destroy
  has_many :joined_rooms, through: :joinables, source: :room

  # Global user broadcasts are disabled until presence subscriptions are scoped.

  enum :role, %i[user admin]
  enum :status, %i[offline away online]

  after_commit :add_default_avatar, on: %i[ create update ]

  after_initialize :set_default_role, if: :new_record?

  def avatar_thumbnail
    avatar.variant(resize_to_limit: [150, 150]).processed
  end

  def chat_thumbnail
    avatar.variant(resize_to_limit: [50, 50]).processed
  end

  def nav_thumbnail
    avatar.variant(resize_to_limit: [45, 45]).processed
  end

  def has_joined_room(room)
    joined_rooms.include?(room)
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

  def avatar_constraints
    return unless avatar.attached?

    blob = avatar.blob
    unless %w[image/jpeg image/png image/webp].include?(blob.content_type)
      errors.add(:avatar, "must be a JPEG, PNG or WebP image")
    end
    errors.add(:avatar, "must be at most 5 MB") if blob.byte_size > 5.megabytes
  end

  def add_default_avatar
    return if avatar.attached?

    avatar.attach(
      io: File.open(Rails.root.join('app', 'assets', 'images', 'default_profile.jpg')),
      filename: 'default_profile.jpg',
      content_type: 'image/jpeg'
    )
  end

  def set_default_role
    self.role ||= :user
  end
end
