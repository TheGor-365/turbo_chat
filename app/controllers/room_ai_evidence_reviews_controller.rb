# frozen_string_literal: true

# FCC-2e.2a: explicit personal review of an exact eligible message version.
# No message transmission, provider call or group approval side effect.
class RoomAiEvidenceReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :rate_limit_review

  def create
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    fields = params.require(:review).permit(
      :message_id, :source_version, :stance, :request_key
    )
    snapshot = AiWorkspace::ConversationCoverageSnapshotV2.new(
      access: AiWorkspace::RoomContextAccess::Independent.new)
    result = AiWorkspace::EvidenceReviewRecorderV1.new(snapshot: snapshot).call(
      room: room, actor: current_user,
      message_id: fields[:message_id],
      source_version: fields[:source_version],
      stance: fields[:stance], request_key: fields[:request_key]
    )
    render json: result
  rescue AiWorkspace::Errors::Unauthorized, AiWorkspace::Errors::ConsentRequired
    head :forbidden
  rescue AiWorkspace::Errors::InvalidSelection, ActionController::ParameterMissing,
    ActiveRecord::RecordInvalid
    render json: { error: "Personal review unavailable or source changed." },
      status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: "Conflicting review request key." },
      status: :conflict
  end

  private

  def rate_limit_review
    enforce_request_limit(scope: "ai-personal-evidence-review",
      limit: 12, period: 60.seconds)
  end
end
