# frozen_string_literal: true

# Manual, single-use answer generation; never auto-sends or creates messages.
class RoomAiAnswersController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_requests

  def create
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return render(json: { error: "ai_not_enabled" },
      status: :service_unavailable) unless AiWorkspace::AnswerGeneration.enabled?

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)
    input = params[:answer]
    return head :unprocessable_entity unless input.is_a?(ActionController::Parameters) &&
      input.keys.sort == %w[confirmed draft_text expected_goal_revision goal_source request_id]
    return head :unprocessable_entity unless
      input[:confirmed] == "1" &&
      input[:goal_source] == "room_instructions" &&
      input[:draft_text].is_a?(String) && input[:draft_text].strip.empty? &&
      input[:expected_goal_revision].is_a?(Integer) &&
      input[:expected_goal_revision].between?(1, 1_000_000_000)

    result = AiWorkspace::AnswerGeneration.new.call(actor: current_user, room: room,
      request_id: input[:request_id],
      expected_goal_revision: input[:expected_goal_revision],
      confirmed: input[:confirmed], draft_text: input[:draft_text])
    render json: {
      mode: "answer", text: result.text, model: result.model,
      cost_usd: format("%.6f", result.cost_ticks / 10_000_000_000.0),
      source_ids: result.source_ids, goal_revision: result.goal_revision,
      provenance_token: AiWorkspace::DraftProvenance.issue(
        actor: current_user, room: room, source_text: result.text,
        answer_context: {
          "request_id" => result.request_id,
          "goal_revision" => result.goal_revision,
          "fingerprint" => result.fingerprint
        }),
      message_sent: false, automatic_send_active: false
    }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired
    render json: { error: "context_consent_required" }, status: :unprocessable_entity
  rescue AiWorkspace::Errors::InvalidSelection, AiWorkspace::Errors::InvalidPreset
    render json: { error: "invalid_or_stale_input" }, status: :unprocessable_entity
  rescue AiWorkspace::Errors::BudgetExceeded
    render json: { error: "budget_unavailable" }, status: :too_many_requests
  rescue AiWorkspace::Errors::ProviderUnavailable
    render json: { error: "provider_unavailable" }, status: :service_unavailable
  end

  private

  def limit_requests
    enforce_request_limit(scope: "ai-answer-generation", limit: 2,
      period: 60.seconds)
  end
end
