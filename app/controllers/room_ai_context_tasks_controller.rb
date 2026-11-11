# frozen_string_literal: true

class RoomAiContextTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_generation

  def create
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    unless AiWorkspace::ContextTaskGeneration.enabled?
      return render json: { error: "Context tasks unavailable." }, status: :service_unavailable
    end

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)
    details = params.require(:task).permit(:kind, :consent, :request_id, :hint, :source_token, source_ids: [])
    output = AiWorkspace::ContextTaskGeneration.new.call(
      actor: current_user, room: room, kind: details[:kind],
      request_id: details[:request_id], confirmed: details[:consent], hint: details[:hint],
      source_token: details[:source_token], selected_ids: details[:source_ids]
    )
    # Check existence and room ownership of every citation after inference.
    # Membership and grants can change while the provider is processing.
    AiWorkspace::RoomContextAccess.new.authorize!(room: room.reload, actor: current_user)
    links = AiWorkspace::SourceLinks.for_room!(room: room, ids: output.source_ids)
    render json: { text: output.text, kind: output.kind, model: output.model,
      source_message_ids: output.source_ids, source_links: links,
      omitted_context_messages: output.omitted,
      evidence_review: output.evidence_review,
      structured_review: output.structured_review,
      cost_usd: format("%.6f", output.cost_ticks / 10_000_000_000.0) }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::BudgetExceeded
    render json: { error: "AI budget unavailable or exhausted." }, status: :too_many_requests
  rescue AiWorkspace::Errors::ConsentRequired
    render json: { error: "All current participants must enable AI context." },
      status: :unprocessable_entity
  rescue AiWorkspace::Errors::InvalidSelection, ActionController::ParameterMissing
    render json: { error: "Invalid task, note or permitted context." },
      status: :unprocessable_entity
  rescue AiWorkspace::Errors::ProviderUnavailable
    render json: { error: "AI output unavailable; nothing saved." }, status: :service_unavailable
  end

  private

  def limit_generation
    enforce_request_limit(scope: "ai-context-task", limit: 2, period: 60.seconds)
  end
end
