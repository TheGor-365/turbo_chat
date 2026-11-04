class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_direct_room_creation, only: :start_conversation

  # A conversation is created only by POST; GET /user/:id no longer mutates DB.
  # The browser uses a CSRF-protected button and is redirected to the room.
  def start_conversation
    recipient = User.find(params[:id])
    return redirect_to rooms_path, status: :see_other if recipient == current_user

    ids = [current_user.id, recipient.id].sort
    room_name = "private_#{ids.join('_')}"
    room = Room.create_private_room([current_user, recipient], room_name)

    redirect_to room_path(room), status: :see_other
  end

  private

  def limit_direct_room_creation
    enforce_request_limit(scope: "direct-room-create", limit: 10, period: 60.seconds)
  end
end
