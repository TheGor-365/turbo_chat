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
    response.headers["Cache-Control"] = "private, no-store"
    head :no_content
  end
end
