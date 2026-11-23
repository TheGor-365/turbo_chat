# Per-account synchronization signals for the conversation list. Never send
# message bodies, peer identities, or a client-selected user/room identifier.
# The browser fetches an ACL-checked snapshot after each small signal.
class RoomInboxChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    stream_from self.class.stream_name(current_user.id)
  end

  def self.stream_name(user_id)
    "room-inbox:user:#{user_id}"
  end

  def self.notify(user)
    return unless user&.persisted?

    ActionCable.server.broadcast(stream_name(user.id), { type: "changed" })
  end

  # Membership invalidation is private to each existing room member's own
  # inbox stream. Never put a room ID, roster or personal data on the wire.
  def self.notify_membership(room)
    room.participants.includes(:user).each do |participant|
      user = participant.user
      next unless user&.persisted?

      ActionCable.server.broadcast(stream_name(user.id),
        { type: "membership_changed" })
    end
  end
end
