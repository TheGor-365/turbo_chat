class Room < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validate :public_name_must_not_use_private_prefix

  scope :public_rooms, -> { where(is_private: false) }
  after_update_commit { broadcast_if_public }

  has_many :messages
  has_many :conversation_read_states, dependent: :destroy
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
          room = find_or_create_by!(name: room_name) { |record| record.is_private = true }
          room.lock!

          raise ActiveRecord::RecordInvalid, room unless room.is_private?
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

  def public_name_must_not_use_private_prefix
    if !is_private? && name.to_s.start_with?("private_")
      errors.add(:name, "is reserved for direct conversations")
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
