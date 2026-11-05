class RoomPresenceController < ApplicationController
  before_action :authenticate_user!

  # Only the currently authorized private conversation partner is observable.
  # Never accept an arbitrary user_id or expose the global user directory.
  def show
    room = Room.find(params[:id])
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    peer_id = room.participants.where.not(user_id: current_user.id).pick(:user_id)
    return head :not_found unless peer_id

    status = PresenceRegistry.new.status(room_id: room.id, user_id: peer_id)
    response.headers["Cache-Control"] = "private, no-store"
    render json: { status: status }
  rescue Redis::BaseError => error
    Rails.logger.warn("Presence snapshot unavailable: #{error.class}")
    response.headers["Cache-Control"] = "private, no-store"
    render json: { status: "unavailable" }, status: :service_unavailable
  end
end
