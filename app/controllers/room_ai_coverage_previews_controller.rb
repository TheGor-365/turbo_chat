# frozen_string_literal: true

# FCC-2b: on-demand inventory only; never calls a model or reserves budget.
# The endpoint is intentionally separate from the nine-excerpt Grok preview.
class RoomAiCoveragePreviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_coverage_preview

  def show
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    preview = AiWorkspace::ConversationCoveragePreviewV1.new.call(
      room: room, actor: current_user,
      page: params[:page], page_size: params[:page_size], token: params[:token]
    )
    render json: preview
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired, AiWorkspace::Errors::InvalidSelection
    # Never echo submitted tokens, private sources, missing grants or
    # former-member identities in an error response.
    render json: { error: "Coverage preview unavailable or changed." },
      status: :unprocessable_entity
  end

  private

  def limit_coverage_preview
    enforce_request_limit(scope: "ai-coverage-preview", limit: 8, period: 60.seconds)
  end
end
