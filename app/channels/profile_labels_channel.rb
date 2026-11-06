# Real-time public chat labels, scoped to each authenticated account.
# No client-provided user IDs, private messages, email or global user stream.
class ProfileLabelsChannel < ApplicationCable::Channel
  MAX_SYNC_PEERS = 500

  def subscribed
    return reject unless current_user

    stream_from self.class.stream_name(current_user.id)
    transmit(type: "snapshot", profiles: self.class.visible_profiles(current_user))
  end

  def self.stream_name(user_id)
    "profile-labels:user:#{user_id}"
  end

  # Restore labels if an event was missed while the browser was disconnected.
  def self.visible_profiles(user)
    peers = User.where(id: peer_ids_for(user)).order(:id).limit(MAX_SYNC_PEERS)
    ([user] + peers.to_a).uniq(&:id).map { |person| { user_id: person.id, label: person.chat_label } }
  end

  def self.broadcast_change(user)
    return unless user&.persisted?

    payload = { type: "profile_changed", user_id: user.id, label: user.chat_label }
    [user.id, *peer_ids_for(user)].uniq.each do |recipient_id|
      ActionCable.server.broadcast(stream_name(recipient_id), payload)
      # Refresh the server-authoritative DM list without sending its contents.
      ActionCable.server.broadcast(RoomInboxChannel.stream_name(recipient_id), { type: "changed" })
    end
  end

  def self.peer_ids_for(user)
    own_private_rooms = Participant.where(user_id: user.id).select(:room_id)
    Participant.joins(:room)
      .where(room_id: own_private_rooms, rooms: { is_private: true })
      .where.not(user_id: user.id)
      .distinct.pluck(:user_id)
  end
end
