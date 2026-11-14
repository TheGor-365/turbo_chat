# frozen_string_literal: true

class RoomAiDraftsController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_generation

  def create
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return render(json: { error: "AI generation disabled." }, status: :service_unavailable) unless
      AiWorkspace::ManualDraftGeneration.enabled?

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.accessible_to?(current_user)
    draft = params.require(:draft).permit(:text, :preset_id, :consent, :request_id, :target_locale)
    result = AiWorkspace::ManualDraftGeneration.new.call(
      actor: current_user, room: room, draft_text: draft[:text],
      preset_id: draft[:preset_id], request_id: draft[:request_id],
      confirmed: draft[:consent], target_locale: draft[:target_locale]
    )
    render json: { text: result.text, model: result.model,
      cost_usd: format("%.6f", result.cost_ticks / 10_000_000_000.0) }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::BudgetExceeded
    render json: { error: "AI request budget unavailable or exhausted." }, status: :too_many_requests
  rescue AiWorkspace::Errors::ConsentRequired
    render json: { error: "Explicit consent required." }, status: :unprocessable_entity
  rescue AiWorkspace::Errors::InvalidPreset, AiWorkspace::Errors::InvalidSelection,
    ActionController::ParameterMissing
    render json: { error: "Invalid draft or preset." }, status: :unprocessable_entity
  rescue AiWorkspace::Errors::ProviderUnavailable
    render json: { error: "AI provider unavailable. Draft unchanged." }, status: :service_unavailable
  end

  private

  def limit_generation
    enforce_request_limit(scope: "ai-manual-generation", limit: 2, period: 60.seconds)
  end
end
