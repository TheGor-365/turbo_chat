# frozen_string_literal: true

# Read-only, account-scoped counts of offline outcome jobs. Text, messages,
# prompts and source IDs never enter this endpoint.
class RoomAiAutomationOutcomesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_private_room!
  before_action :limit_status_requests

  def index
    scope = AiAutomationWorkItem.joins(:ai_automation_run).where(
      ai_automation_runs: { room_id: @room.id, user_id: current_user.id,
        run_kind: "conversation_outcome" })
    render json: {
      completed: scope.where(state: "completed").count,
      pending: scope.where(state: %w[queued leased]).count,
      blocked: scope.where(state: "blocked").count,
      documents_url: room_ai_deliverables_path(@room),
      provider_called: false, automatic_send_active: false
    }
  end

  private

  def authorize_private_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    AiWorkspace::RoomContextAccess.new.authorize!(room: @room, actor: current_user)
  rescue AiWorkspace::Errors::Unauthorized, AiWorkspace::Errors::ConsentRequired
    head :forbidden
  end

  def limit_status_requests
    enforce_request_limit(scope: "ai-outcome-status", limit: 15, period: 60.seconds)
  end
end
