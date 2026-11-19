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
end
