# frozen_string_literal: true

# FCC-2d: manual, zero-provider-cost evidence candidates. Uses POST to keep
# the user's search text out of URLs, browser history and routine access logs.
class RoomAiEvidenceSearchesController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_evidence_search

  def create
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    snapshot = AiWorkspace::ConversationCoverageSnapshotV2.new(
      access: AiWorkspace::RoomContextAccess::Independent.new)
    result = AiWorkspace::ConversationEvidenceSearchV1.new(snapshot: snapshot).call(
      room: room, actor: current_user, query: params[:evidence_query]
    )
    render json: result
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired, AiWorkspace::Errors::InvalidSelection
    render json: { error: "Evidence search unavailable or history changed." },
      status: :unprocessable_entity
  end

  private

  def limit_evidence_search
    enforce_request_limit(scope: "ai-evidence-search", limit: 6, period: 60.seconds)
  end
end
