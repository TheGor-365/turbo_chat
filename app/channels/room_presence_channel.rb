# Room-only event channel. Audience is the authenticated recipient inside
# their private DM. No global user status or client-selected peer identities.
class RoomPresenceChannel < ApplicationCable::Channel
  MAX_HEARTBEATS_PER_MINUTE = 30

  def subscribed
    @room = Room.find_by(id: params[:room_id])
    return reject unless @room&.is_private? && @room.accessible_to?(current_user)

    @token = SecureRandom.hex(16)
    stream_from self.class.stream_name(@room.id, current_user.id)
  end

  # ActionCable dispatches payload only when this action has arity exactly 1.
  def heartbeat(data)
    return unless @token && @room&.is_private? && @room.accessible_to?(current_user)
    # A separate tab may change the user's privacy settings while this
    # subscription remains open. Never recreate Redis presence after opt-out.
    return unless current_user.reload.share_presence?
    return if RequestThrottle.exceeded?(
      scope: "dm-presence", identity: "user:#{current_user.id}:room:#{@room.id}",
      limit: MAX_HEARTBEATS_PER_MINUTE, period: 60.seconds
    )

    transition = PresenceRegistry.new.heartbeat(
      room_id: @room.id, user_id: current_user.id, token: @token,
      active: data["active"] == true || data[:active] == true
    )
    notify_other_participant if transition[:previous] != transition[:current]
  rescue Redis::BaseError => error
    Rails.logger.warn("Presence heartbeat unavailable: #{error.class}")
  end

  def unsubscribed
    return unless @token && @room

    transition = PresenceRegistry.new.leave(
      room_id: @room.id, user_id: current_user.id, token: @token
    )
    notify_other_participant if transition[:previous] != transition[:current]
  rescue Redis::BaseError => error
    Rails.logger.warn("Presence disconnect unavailable: #{error.class}")
  end

  def self.stream_name(room_id, recipient_id)
    "room-presence:#{room_id}:user:#{recipient_id}"
  end

  private

  def notify_other_participant
    @room.participants.where.not(user_id: current_user.id).pluck(:user_id).each do |recipient_id|
      ActionCable.server.broadcast(
        self.class.stream_name(@room.id, recipient_id),
        { type: "presence_changed" }
      )
    end
  end
end
