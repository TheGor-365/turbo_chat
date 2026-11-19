# frozen_string_literal: true

# Server-derived readiness for the ONE versioned room-instruction source.
# Does not expose private goal records, alter consents or contact AI.
class RoomAiInstructionGoalsController < ApplicationController
  before_action :authenticate_user!

  def show
    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    goal = AiWorkspace::RoomInstructionGoal.load!(room: room, actor: current_user)
    render json: { configured: true, current_revision: goal.revision,
      ai_answer_available: false }
  rescue AiWorkspace::Errors::InvalidSelection
    render json: { configured: false, current_revision: 0,
      reason: "missing_or_invalid_room_instruction", ai_answer_available: false }
  end
end
