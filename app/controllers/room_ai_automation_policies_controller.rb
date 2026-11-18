# frozen_string_literal: true

# Three product modes: AI proposal requiring Apply, full automatic reply,
# and independent summary/document automation. Configuration is NOT execution.
class RoomAiAutomationPoliciesController < ApplicationController
  FIELDS = %w[base_revision reply_delay_seconds reply_mode summary_after_messages summary_kind summary_mode].freeze

  before_action :authenticate_user!
  before_action :load_private_room!
  before_action :limit_updates, only: %i[update destroy]

  def show
    render_snapshot(AiAutomationPolicy.find_by(room: @room, user: current_user))
  end

  def update
    raw = params[:policy]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys.sort == FIELDS

    base = strict_revision(raw[:base_revision])
    return head :unprocessable_entity unless base

    properties = raw.permit(:reply_mode, :summary_mode, :summary_kind,
      :summary_after_messages, :reply_delay_seconds).to_h.symbolize_keys
    unless properties.keys.sort == %i[reply_delay_seconds reply_mode summary_after_messages summary_kind summary_mode]
      return head :unprocessable_entity
    end
    threshold = strict_number(properties[:summary_after_messages], min: 5, max: 200)
    delay = strict_number(properties[:reply_delay_seconds], min: 10, max: 600)
    return head :unprocessable_entity unless threshold && delay

    properties[:summary_after_messages] = threshold
    properties[:reply_delay_seconds] = delay
    return head :unprocessable_entity unless
      AiAutomationPolicy::REPLY_MODES.include?(properties[:reply_mode]) &&
      AiAutomationPolicy::SUMMARY_MODES.include?(properties[:summary_mode]) &&
      AiAutomationPolicy::SUMMARY_KINDS.include?(properties[:summary_kind])

    result = apply_update(base: base, properties: properties)
    return render_conflict(result.fetch(:revision)) if result.key?(:revision)

    render_snapshot(result.fetch(:policy), changed: result.fetch(:changed))
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  end

  # Separate explicit off switch; preserve the revision record for stale-tab
  # detection. Never enqueue a side effect or delete conversation data.
  def destroy
    raw = params[:policy]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys == ["base_revision"]

    base = strict_revision(raw[:base_revision])
    return head :unprocessable_entity unless base
    result = apply_update(base: base, properties: { reply_mode: "off", summary_mode: "off" },
      disable: true)
    return render_conflict(result.fetch(:revision)) if result.key?(:revision)

    render_snapshot(result.fetch(:policy), changed: result.fetch(:changed))
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  end

  private

  def load_private_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_updates
    enforce_request_limit(scope: "ai-automation-policy", limit: 12, period: 60.seconds)
  end

  def strict_number(value, min:, max:)
    return value if value.is_a?(Integer) && value.between?(min, max)
    return nil unless value.is_a?(String) && value.match?(/\A(?:0|[1-9]\d{0,8})\z/)

    number = value.to_i
    number if number.between?(min, max)
  end

  def strict_revision(value)
    strict_number(value, min: 0, max: 1_000_000_000)
  end

  def apply_update(base:, properties:, disable: false)
    outcome = nil
    @room.with_lock do
      raise AiWorkspace::Errors::Unauthorized unless @room.reload.accessible_to?(current_user)
      policy = AiAutomationPolicy.find_by(room: @room, user: current_user)
      old_revision = policy&.revision || 0

      if base != old_revision
        outcome = { revision: old_revision }
      elsif disable && !policy
        outcome = { policy: nil, changed: false }
      else
        policy ||= AiAutomationPolicy.new(room: @room, user: current_user)
        policy.assign_attributes(properties)
        changed = policy.new_record? || policy.changed?
        if changed
          policy.revision = old_revision + 1
          policy.save!
        end
        outcome = { policy: policy, changed: changed }
      end
    end
    outcome
  end

  def render_conflict(current_revision)
    render json: { error: "stale_automation_policy", current_revision: current_revision },
      status: :conflict
  end

  def render_snapshot(policy, changed: false)
    render json: { configured: policy.present?,
      policy: policy&.public_snapshot,
      current_revision: policy&.revision || 0, changed: changed,
      execution: policy ? policy.execution_status : {
        reply_generation_active: false, unattended_send_active: false,
        scheduled_summaries_active: false, configuration_only: true,
        available_manual_previews: AiAutomationPolicy::PREVIEW_KINDS } }
  end
end
