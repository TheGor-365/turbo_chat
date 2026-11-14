class PagesController < ApplicationController
  # Home is a read-only entry point. Only current memberships may contribute
  # metadata; never change presence, mark messages read or render chat bodies.
  def home
    return unless user_signed_in?

    private_ids = Room.where(is_private: true).joins(:participants)
      .where(participants: { user_id: current_user.id }).select(:id)
    public_ids = Room.where(is_private: false).joins(:joinables)
      .where(joinables: { user_id: current_user.id }).select(:id)

    @home_rooms = Room.where(id: private_ids).or(Room.where(id: public_ids))
      .includes(participants: :user)
      .order(last_message_at: :desc, id: :desc).limit(6).to_a

    @home_unread_alerts = Notification.visible_to(current_user).unread.count

    room_ids = @home_rooms.map(&:id)
    @home_unread_counts = if room_ids.empty?
      {}
    else
      cursor_join = Message.sanitize_sql_array([
        "LEFT JOIN conversation_read_states ON conversation_read_states.room_id = messages.room_id AND conversation_read_states.user_id = ?",
        current_user.id
      ])
      Message.where(room_id: room_ids)
        .where.not(user_id: current_user.id)
        .joins(cursor_join)
        .where("messages.id > COALESCE(conversation_read_states.last_read_message_id, 0)")
        .group("messages.room_id").count
    end

    # Room names and peer labels are user-specific, even though no message
    # bodies are rendered. Never persist the authenticated Home in caches.
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end
end
