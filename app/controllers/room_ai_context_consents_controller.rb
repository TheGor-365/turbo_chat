# frozen_string_literal: true

class RoomAiContextConsentsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorized_private_room
  before_action :no_store

  def show
    return render_disabled unless AiWorkspace::RoomContextAccess.available?
    return render_ineligible unless eligible_membership?

    render json: serialize(AiWorkspace::RoomContextAccess.new.status(room: @room, actor: current_user))
  end

  def update
    return render_disabled unless AiWorkspace::RoomContextAccess.available?
    return render_ineligible(status: :unprocessable_entity) unless eligible_membership?

    # A grant authorizes external processing of this member's messages,
    # including previous messages. It cannot be granted for another user.
    details = params.require(:consent).permit(:enabled)
    enabled = details[:enabled]
    unless %w[0 1].include?(enabled)
      return render json: { error: "Choose enabled or disabled." }, status: :unprocessable_entity
    end
    entry = AiRoomContextConsent.find_or_initialize_by(
      room_id: @room.id, user_id: current_user.id
    )
    enabled == "1" ? entry.grant! : entry.revoke!
    render json: serialize(AiWorkspace::RoomContextAccess.new.status(room: @room, actor: current_user))
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    render json: { error: "Context preference could not be saved." }, status: :conflict
  end

  private

  def authorized_private_room
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)
  end

  def eligible_membership?
    # A private conversation with only its owner is not eligible for context
    # transfer. Return a safe, actionable status instead of an HTTP 500.
    @member_count = @room.participants.distinct.count(:user_id)
    @member_count.between?(2, AiWorkspace::RoomContextAccess::MAX_PARTICIPANTS)
  end

  def render_ineligible(status: :ok)
    reason = @member_count < 2 ? "not_enough_members" : "too_many_members"
    render json: {
      enabled: false, ready: false, available: false,
      members: @member_count, granted: 0, reason: reason,
      participants: participant_statuses
    }, status: status
  end

  def serialize(status)
    { enabled: status.enabled, ready: status.ready,
      members: status.members, granted: status.granted,
      available: AiWorkspace::ContextReplyGeneration.enabled?,
      participants: participant_statuses }
  end

  # Member-only disclosure. Never return emails or data from other rooms.
  # This list is read-only; each user can change only their own grant.
  def participant_statuses
    members = @room.participants.includes(:user).order(:user_id).to_a
    ids = members.map(&:user_id)
    enabled_ids = AiRoomContextConsent.where(room_id: @room.id, user_id: ids,
      revoked_at: nil).where.not(granted_at: nil).pluck(:user_id)
    members.map do |entry|
      { id: entry.user_id, name: entry.user.chat_label,
        enabled: enabled_ids.include?(entry.user_id) }
    end
  end

  def render_disabled
    render json: { enabled: false, ready: false, available: false },
      status: :service_unavailable
  end

  def no_store
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end
end
