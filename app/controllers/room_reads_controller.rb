class RoomReadsController < ApplicationController
  before_action :authenticate_user!

  # Read acknowledgement is a CSRF-protected POST, never a GET side effect.
  # It only advances to a real message from the currently authorized room.
  def update
    room = Room.find(params[:id])
    return head :forbidden unless room.accessible_to?(current_user)

    cursor = params[:last_read_message_id].to_s
    return head :bad_request unless cursor.match?(/\A[1-9]\d{0,17}\z/)

    message = room.messages.find_by(id: cursor.to_i)
    return head :unprocessable_entity unless message

    state = ConversationReadState.create_or_find_by!(room: room, user: current_user)
    state.advance_to!(message)
    # One authenticated read cursor also acknowledges its corresponding
    # personal events. A stale tab cannot accidentally read newer events.
    Notification.visible_to(current_user).unread.where(room_id: room.id)
      .where("message_id <= ?", state.last_read_message_id)
      .update_all(read_at: Time.current, updated_at: Time.current)
    RoomInboxChannel.notify(current_user)
    response.headers["Cache-Control"] = "private, no-store"
    head :no_content
  end
end
