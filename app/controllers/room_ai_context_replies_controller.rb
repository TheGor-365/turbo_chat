# frozen_string_literal: true

class RoomAiContextRepliesController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_generation

  # Never creates a Message. Clicking this button means consent to ONE xAI
  # inference request; sending the suggested text to peers is separate.
  def create
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    unless AiWorkspace::ContextReplyGeneration.enabled?
      return render json: { error: "Contextual replies unavailable." }, status: :service_unavailable
    end

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)
    details = params.require(:reply).permit(:consent, :request_id, :hint, :source_token, source_ids: [])
    output = AiWorkspace::ContextReplyGeneration.new.call(
      actor: current_user, room: room, request_id: details[:request_id],
      confirmed: details[:consent], hint: details[:hint],
      source_token: details[:source_token], selected_ids: details[:source_ids]
    )
    AiWorkspace::RoomContextAccess.new.authorize!(room: room.reload, actor: current_user)
    links = AiWorkspace::SourceLinks.for_room!(room: room, ids: output.source_ids)
    render json: {
      text: output.text, model: output.model, source_message_ids: output.source_ids,
      source_links: links,
      omitted_context_messages: output.omitted,
      cost_usd: format("%.6f", output.cost_ticks / 10_000_000_000.0)
    }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::BudgetExceeded
    render json: { error: "AI request budget unavailable or exhausted." }, status: :too_many_requests
  rescue AiWorkspace::Errors::ConsentRequired
    render json: { error: "Context requires permission from every participant." }, status: :unprocessable_entity
  rescue AiWorkspace::Errors::InvalidSelection, ActionController::ParameterMissing
    render json: { error: "No safe relevant context or invalid reply note." }, status: :unprocessable_entity
  rescue AiWorkspace::Errors::ProviderUnavailable
    render json: { error: "AI provider unavailable. Draft unchanged." }, status: :service_unavailable
  end

  private

  def limit_generation
    enforce_request_limit(scope: "ai-context-reply", limit: 2, period: 60.seconds)
  end
end
