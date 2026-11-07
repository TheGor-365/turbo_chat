# Ephemeral direct-message typing signals. Unlike chat messages, this data is
# never written to PostgreSQL, cached as a draft, or shared globally.
class RoomTypingChannel < ApplicationCable::Channel
  MAX_SIGNALS_PER_MINUTE = 60

  def subscribed
    @room = Room.find_by(id: params[:room_id])
    return reject unless @room&.direct_message? && @room.accessible_to?(current_user)

    stream_from self.class.stream_name(@room.id, current_user.id)
  end

  # Ignore client-supplied user IDs, room IDs, text, and arbitrary payloads.
  # Resolve sender and recipients from the authenticated ActionCable session.
  def typing
    broadcast_indicator("typing")
  end

  def stopped
    broadcast_indicator("stopped")
  end

  def self.stream_name(room_id, recipient_id)
    "room-typing:#{room_id}:user:#{recipient_id}"
  end

  private

  def broadcast_indicator(event)
    # Membership is rechecked on each event, not just at subscription time.
    # A copied subscription cannot keep signaling after access is revoked.
    return unless @room&.direct_message? && @room.accessible_to?(current_user)

    throttled = RequestThrottle.exceeded?(
      scope: "dm-typing", identity: "user:#{current_user.id}:room:#{@room.id}",
      limit: MAX_SIGNALS_PER_MINUTE, period: 60.seconds
    )
    return if throttled

    # Only existing DM participants receive signals. Do not relay to a
    # room-wide or public channel, and never broadcast the typed content.
    recipient_ids = @room.participants.where.not(user_id: current_user.id).pluck(:user_id)
    recipient_ids.each do |recipient_id|
      ActionCable.server.broadcast(
        self.class.stream_name(@room.id, recipient_id),
        { type: event, room_id: @room.id, user_id: current_user.id }
      )
    end
  end
end
