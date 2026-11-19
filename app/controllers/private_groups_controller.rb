class PrivateGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_group_changes

  def create
    room_name = params.require(:private_group).fetch(:name, "").to_s
    room = nil
    Room.transaction do
      room = Room.create!(name: room_name, kind: "private_group",
        is_private: true, owner: current_user)
      room.participants.create!(user: current_user, group_role: "owner")
    end
    RoomInboxChannel.notify(current_user)
    redirect_to room_path(room), status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to rooms_path, alert: "Could not create private group. Use a unique name of 2–60 characters.", status: :see_other
  end

  def invite
    room = owned_group
    return head :not_found unless room

    recipient_id = params[:user_id].to_s
    return head :bad_request unless recipient_id.match?(/\A[1-9]\d{0,17}\z/)

    recipient = User.find_by(id: recipient_id.to_i)
    return head :not_found unless recipient
    return head :unprocessable_entity if recipient == current_user || room.accessible_to?(recipient)

    room.with_lock do
      invitation = room.private_group_invitations.find_or_initialize_by(user: recipient)
      invitation.invited_by = current_user
      invitation.status = "pending"
      invitation.save!
    end

    RoomInboxChannel.notify(recipient)
    redirect_to room_path(room), status: :see_other,
      flash: { private_group_invite_sent: "Invitation sent" }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    head :unprocessable_entity
  end

  # Public and invite-only rooms use the same Leave affordance.
  # Membership changes must not delete the room, messages or media.
  def leave
    room = Room.private_groups.find_by(id: params[:id])
    return head :not_found unless room

    departing = nil
    successor = nil
    revoked_ids = []
    room.with_lock do
      departing = room.participants.find_by(user_id: current_user.id)
      if departing && room.owner_id == current_user.id
        successor = room.participants.where.not(user_id: current_user.id).order(:id).first
        if successor
          # Transfer the owner's rights atomically before removing their row.
          room.update!(owner_id: successor.user_id)
          successor.update!(group_role: "owner")
          # Pending invitations issued under the old owner do not transfer.
          revoked_ids = room.private_group_invitations.pending.pluck(:user_id)
          room.private_group_invitations.pending.update_all(
            status: "revoked", updated_at: Time.current
          )
        end
      end
      departing.destroy! if departing && room.owner_id != current_user.id
    end

    return head :not_found unless departing
    if room.owner_id == current_user.id
      return redirect_to room_path(room), status: :see_other,
        flash: { private_group_leave_error: "Invite another member before leaving as the last owner." }
    end

    RoomInboxChannel.notify(current_user)
    RoomInboxChannel.notify(room.owner)
    revoked_ids.each { |id| RoomInboxChannel.notify(User.find(id)) }
    # Invalidate previously authorized room subscriptions, as public Leave does.
    ActionCable.server.remote_connections.where(current_user: current_user).disconnect
    redirect_to rooms_path, status: :see_other
  end

  def remove_member
    room = owned_group
    return head :not_found unless room

    member_id = params[:user_id].to_s
    return head :bad_request unless member_id.match?(/\A[1-9]\d{0,17}\z/)
    return head :forbidden if member_id.to_i == room.owner_id

    participant = room.participants.find_by(user_id: member_id.to_i)
    return head :not_found unless participant

    member = participant.user
    participant.destroy!
    RoomInboxChannel.notify(member)
    RoomInboxChannel.notify(current_user)
    # Existing subscriptions were authorized at connect time. Force them to
    # resubscribe, so former members cannot continue receiving group events.
    ActionCable.server.remote_connections.where(current_user: member).disconnect
    redirect_to room_path(room), notice: "Member removed", status: :see_other
  end

  private

  def owned_group
    Room.private_groups.find_by(id: params[:id], owner_id: current_user.id)
  end

  def limit_group_changes
    enforce_request_limit(scope: "private-group-change", limit: 12, period: 60.seconds)
  end
end
