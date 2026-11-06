class User < ApplicationRecord

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  scope :all_except, ->(user) { where.not(id: user) }

  has_many :messages
  has_many :conversation_read_states, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :conversation_notification_preferences, dependent: :destroy
  has_many :message_reactions, dependent: :destroy
  has_one_attached :avatar
  before_validation :normalize_display_name
  # Optional labels are not unique handles and are never used for ACL.
  validates :display_name, length: { in: 2..48 },
    format: { with: /\A[\p{L}\p{N}][\p{L}\p{M}\p{N} ._'\-]*\z/,
      message: "may contain letters, numbers, spaces, dots, underscores, apostrophes and hyphens" },
    allow_nil: true
  validate :avatar_constraints
  has_many :joinables, dependent: :destroy
  has_many :joined_rooms, through: :joinables, source: :room

  # Label events are sent only to the account and its current private-chat peers.
  after_update_commit :notify_chat_label_change, if: :saved_change_to_display_name?

  enum :role, %i[user admin]
  enum :status, %i[offline away online]

  after_initialize :set_default_role, if: :new_record?

  # A login email never becomes a public chat identity.
  def chat_label
    display_name.presence || "Member ##{id}"
  end

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

  def notify_chat_label_change
    ProfileLabelsChannel.broadcast_change(self)
  end

  def normalize_display_name
    self.display_name = display_name.to_s.squish.presence
  end

  def avatar_constraints
    return unless avatar.attached?

    blob = avatar.blob
    unless %w[image/jpeg image/png image/webp].include?(blob.content_type)
      errors.add(:avatar, "must be a JPEG, PNG or WebP image")
    end
    errors.add(:avatar, "must be at most 5 MB") if blob.byte_size > 5.megabytes
  end

  def set_default_role
    self.role ||= :user
  end
end
