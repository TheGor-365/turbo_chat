class RoomPresenceController < ApplicationController
  before_action :authenticate_user!

  # Only the currently authorized private conversation partner is observable.
  # Never accept an arbitrary user_id or expose the global user directory.
  def show
    room = Room.find(params[:id])
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    peer = room.participants.includes(:user).where.not(user_id: current_user.id).first&.user
    return head :not_found unless peer

    # Appearing offline is deliberately indistinguishable from being offline.
    # Never expose a hidden peer's Redis state or visibility preference.
    status = peer.share_presence? ?
      PresenceRegistry.new.status(room_id: room.id, user_id: peer.id) : "offline"
    response.headers["Cache-Control"] = "private, no-store"
    render json: { status: status }
  rescue Redis::BaseError => error
    Rails.logger.warn("Presence snapshot unavailable: #{error.class}")
    response.headers["Cache-Control"] = "private, no-store"
    render json: { status: "unavailable" }, status: :service_unavailable
  end
end
