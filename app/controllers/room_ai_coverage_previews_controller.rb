# frozen_string_literal: true

# FCC-2b: on-demand inventory only; never calls a model or reserves budget.
# The endpoint is intentionally separate from the nine-excerpt Grok preview.
class RoomAiCoveragePreviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_coverage_preview, only: :show
  before_action :limit_message_preview, only: :message

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

  # One explicitly clicked source. Do not accept arbitrary historical text:
  # the service re-runs the room's consent-scoped coverage and DLP gates.
  def message
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    payload = AiWorkspace::ConversationCoverageMessageV1.new.call(
      room: room, actor: current_user, message_id: params[:message_id]
    )
    render json: payload
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired, AiWorkspace::Errors::InvalidSelection
    render json: { error: "Message preview unavailable or changed." },
      status: :unprocessable_entity
  end

  private

  def limit_message_preview
    enforce_request_limit(scope: "ai-coverage-message-preview", limit: 15, period: 60.seconds)
  end

  def limit_coverage_preview
    enforce_request_limit(scope: "ai-coverage-preview", limit: 8, period: 60.seconds)
  end
end
