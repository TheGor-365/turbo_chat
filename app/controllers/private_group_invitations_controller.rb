class PrivateGroupInvitationsController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_invitation_actions

  def accept
    invite = PrivateGroupInvitation.pending.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless invite

    room = invite.room
    room.with_lock do
      invite.reload
      return head :not_found unless invite.status == "pending" && room.private_group?

      # Capture the pre-join message boundary before granting access.
      last_message = room.messages.order(id: :desc).first
      room.participants.find_or_create_by!(user: current_user) { |p| p.group_role = "member" }
      if last_message
        ConversationReadState.create_or_find_by!(room: room, user: current_user).advance_to!(last_message)
      end
      invite.update!(status: "accepted")
    end
    RoomInboxChannel.notify(current_user)
    RoomInboxChannel.notify(room.owner)
    redirect_to room_path(room), status: :see_other
  end

  def decline
    invite = PrivateGroupInvitation.pending.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless invite

    # Serialize decline against Accept and owner re-invitation. Without the
    # same room lock an older Decline request could overwrite "accepted".
    invite.room.with_lock do
      invite.reload
      return head :not_found unless invite.status == "pending"
      invite.update!(status: "declined")
    end
    RoomInboxChannel.notify(current_user)
    RoomInboxChannel.notify(invite.room.owner)
    redirect_to rooms_path, status: :see_other
  end

  private

  def limit_invitation_actions
    enforce_request_limit(scope: "private-group-invitation", limit: 15, period: 60.seconds)
  end
end
