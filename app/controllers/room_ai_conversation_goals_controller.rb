# frozen_string_literal: true

# Private, personal room goal. Creating/editing/revoking this record never
# invokes a model, enables history consent, changes peers or sends a message.
class RoomAiConversationGoalsController < ApplicationController
  FIELDS = %w[base_revision constraints desired_outcome purpose].freeze

  before_action :authenticate_user!
  before_action :load_room!
  before_action :limit_writes, only: %i[update destroy]

  def show
    goal = AiConversationGoal.find_by(room: @room, user: current_user)
    render_snapshot(goal)
  end

  def update
    raw = params[:goal]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys.sort == FIELDS
    revision = parse_revision(raw[:base_revision])
    return head :unprocessable_entity unless revision

    values = raw.permit(:purpose, :constraints, :desired_outcome).to_h.symbolize_keys
    return head :unprocessable_entity unless values.keys.sort == %i[constraints desired_outcome purpose]
    return head :unprocessable_entity unless values.values.all? { |value| value.is_a?(String) }

    result = nil
    @room.with_lock do
      raise AiWorkspace::Errors::Unauthorized unless @room.reload.accessible_to?(current_user)
      goal = AiConversationGoal.find_or_initialize_by(room: @room, user: current_user)
      actual_revision = goal.persisted? ? goal.revision : 0
      if revision != actual_revision
        result = { conflict: actual_revision }
      else
        goal.assign_attributes(values.merge(active: true))
        changed = goal.new_record? || goal.changed?
        if changed
          goal.revision = actual_revision + 1
          goal.save!
        end
        result = { goal: goal, changed: changed }
      end
    end
    return render_conflict(result[:conflict]) if result.key?(:conflict)
    render_snapshot(result.fetch(:goal), changed: result.fetch(:changed))
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  end

  def destroy
    raw = params[:goal]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys == ["base_revision"]
    revision = parse_revision(raw[:base_revision])
    return head :unprocessable_entity unless revision

    result = nil
    @room.with_lock do
      raise AiWorkspace::Errors::Unauthorized unless @room.reload.accessible_to?(current_user)
      goal = AiConversationGoal.find_by(room: @room, user: current_user)
      actual_revision = goal&.revision || 0
      if revision != actual_revision
        result = { conflict: actual_revision }
      else
        changed = !!goal&.active?
        if changed
          goal.update!(active: false, revision: actual_revision + 1)
        end
        result = { goal: goal, changed: changed }
      end
    end
    return render_conflict(result[:conflict]) if result.key?(:conflict)
    render_snapshot(result[:goal], changed: result.fetch(:changed))
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  end

  private

  def load_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_writes
    enforce_request_limit(scope: "ai-conversation-goals", limit: 12, period: 60.seconds)
  end

  def parse_revision(value)
    return value if value.is_a?(Integer) && value.between?(0, 1_000_000_000)
    return nil unless value.is_a?(String) && value.match?(/\A(?:0|[1-9]\d{0,9})\z/)

    parsed = value.to_i
    parsed if parsed <= 1_000_000_000
  end

  def render_conflict(current_revision)
    render json: { error: "stale_goal_revision", current_revision: current_revision },
      status: :conflict
  end

  def render_snapshot(goal, changed: false)
    active = goal&.active? == true
    render json: { configured: active, goal: active ? goal.public_snapshot : nil,
      current_revision: goal&.revision || 0, changed: changed,
      ai_answer_available: false }
  end
end
