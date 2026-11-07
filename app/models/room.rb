class Room < ApplicationRecord
  KINDS = %w[public_room direct_message private_group].freeze

  before_validation :infer_legacy_kind
  before_validation :normalize_group_or_public_name, unless: :direct_message?
  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, uniqueness: true
  validates :name, length: { in: 2..60 }, unless: :direct_message?
  validate :public_name_must_not_use_private_prefix
  validate :kind_consistent_with_privacy

  belongs_to :owner, class_name: "User", optional: true
  scope :public_rooms, -> { where(is_private: false) }
  scope :direct_messages, -> { where(is_private: true, kind: "direct_message") }
  scope :private_groups, -> { where(is_private: true, kind: "private_group") }

  def public_room?
    !is_private? && kind == "public_room"
  end

  def direct_message?
    is_private? && (kind == "direct_message" || kind.nil?)
  end

  def private_group?
    is_private? && kind == "private_group"
  end

  def owned_by?(user)
    private_group? && user && owner_id == user.id
  end
  after_update_commit { broadcast_if_public }

  has_many :messages
  has_many :conversation_read_states, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :conversation_notification_preferences, dependent: :destroy
  has_many :participants, dependent: :destroy
  has_many :private_group_invitations, dependent: :destroy
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
    users = users.uniq.sort_by(&:id)
    ids = users.map(&:id)
    raise ArgumentError, "Direct conversations require two persisted users" unless ids.size == 2 && ids.all?
    raise ArgumentError, "Invalid direct conversation identifier" unless room_name == "private_#{ids.join('_')}"

    # Room name is unique at the DB level. Retry unique races in a fresh
    # transaction; lock the row while validating and inserting participants.
    5.times do
      begin
        return transaction(requires_new: true) do
          # Serialize creators of the same canonical DM across web workers.
          # A transaction-level PostgreSQL advisory lock avoids the
          # find_or_create_by! validation race before the row is committed.
          lock_key = Digest::SHA256.hexdigest(room_name)[0, 16].to_i(16) & 0x7fff_ffff_ffff_ffff
          bind = ActiveRecord::Relation::QueryAttribute.new("advisory_key", lock_key, ActiveRecord::Type::Integer.new(limit: 8))
          connection.select_value("SELECT pg_advisory_xact_lock($1)", "DM advisory lock", [bind])
          room = find_or_create_by!(name: room_name) { |record| record.is_private = true; record.kind = 'direct_message' }
          room.lock!

          raise ActiveRecord::RecordInvalid, room unless room.direct_message?
          existing_ids = room.participants.pluck(:user_id)
          raise ActiveRecord::RecordInvalid, room if (existing_ids - ids).any?

          ids.each { |id| room.participants.find_or_create_by!(user_id: id) }
          room
        end
      rescue ActiveRecord::RecordNotUnique
        # Another request inserted the same room or participant.
      rescue ActiveRecord::RecordInvalid => error
        # Rails model-level uniqueness validation can race with another
        # transaction before the database unique constraint is reached.
        # Only retry the expected collision, never unrelated validations.
        raise unless error.record.is_a?(Room) &&
          error.record.errors.added?(:name, :taken)
      end
    end

    raise ActiveRecord::RecordNotUnique, "Could not create direct conversation after retries"
  end

  private

  def infer_legacy_kind
    self.kind ||= is_private? ? "direct_message" : "public_room"
  end

  def normalize_group_or_public_name
    self.name = name.to_s.squish
  end

  def public_name_must_not_use_private_prefix
    if !direct_message? && name.to_s.start_with?("private_")
      errors.add(:name, "is reserved for direct conversations")
    end
  end

  def kind_consistent_with_privacy
    if kind == "private_group"
      errors.add(:is_private, "must be true for private groups") unless is_private?
      errors.add(:owner, "is required for private groups") unless owner_id.present?
    elsif kind == "direct_message"
      errors.add(:is_private, "must be true for direct messages") unless is_private?
    elsif kind == "public_room" && is_private?
      errors.add(:is_private, "must be false for public rooms")
    end
  end

  public

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
