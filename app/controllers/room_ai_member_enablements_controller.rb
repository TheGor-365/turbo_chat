# frozen_string_literal: true

# Read-only preference indicators for current private-conversation members.
# Not a provider readiness or author-history permission endpoint.
class RoomAiMemberEnablementsController < ApplicationController
  before_action :authenticate_user!

  def show
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    snapshot = ActiveRecord::Base.uncached do
      room = Room.find_by(id: params[:room_id])
      next unless room && (room.direct_message? || room.private_group?)
      ids = room.participants.distinct.order(:user_id).pluck(:user_id)
      next unless ids.include?(current_user.id)
      settings = AiPersonalEnablement.where(user_id: ids).pluck(:user_id, :enabled).to_h
      # Recheck membership and room scope before returning the snapshot.
      next unless room.reload.is_private? &&
        (room.direct_message? || room.private_group?) &&
        room.participants.distinct.order(:user_id).pluck(:user_id) == ids

      { members: ids.map { |id|
        { user_id: id, enabled: settings.fetch(id, true), configured: settings.key?(id) }
      } }
    end
    return head :not_found unless snapshot

    render json: snapshot
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
