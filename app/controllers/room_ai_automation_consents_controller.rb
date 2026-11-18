# frozen_string_literal: true

# Per-account opt-in to background use, unattended Send and scheduled outcomes.
# This endpoint can only save preferences. It never dispatches a task/provider.
class RoomAiAutomationConsentsController < ApplicationController
  FIELDS = %w[background_context_enabled base_revision scheduled_outcomes_enabled unattended_send_enabled].freeze

  before_action :authenticate_user!
  before_action :load_private_room!
  before_action :limit_updates, only: %i[update destroy]

  def show
    render_snapshot(AiRoomAutomationConsent.find_by(room: @room, user: current_user))
  end

  def update
    raw = params[:consent]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys.sort == FIELDS

    base = strict_revision(raw[:base_revision])
    return head :unprocessable_entity unless base

    properties = raw.permit(:background_context_enabled, :unattended_send_enabled,
      :scheduled_outcomes_enabled).to_h.symbolize_keys
    return head :unprocessable_entity unless properties.keys.sort ==
      %i[background_context_enabled scheduled_outcomes_enabled unattended_send_enabled]
    return head :unprocessable_entity unless properties.values.all? { |v| v == true || v == false }

    apply!(base: base, properties: properties)
  end

  def destroy
    raw = params[:consent]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys == ["base_revision"]
    base = strict_revision(raw[:base_revision])
    return head :unprocessable_entity unless base

    apply!(base: base, properties: {
      background_context_enabled: false, unattended_send_enabled: false,
      scheduled_outcomes_enabled: false })
  end

  private

  def load_private_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def strict_revision(value)
    return value if value.is_a?(Integer) && value.between?(0, 1_000_000_000)
    return nil unless value.is_a?(String) &&
      value.match?(/\A(?:0|[1-9]\d{0,9})\z/)

    value.to_i if value.to_i <= 1_000_000_000
  end

  def limit_updates
    enforce_request_limit(scope: "ai-background-consent", limit: 10, period: 60.seconds)
  end

  def apply!(base:, properties:)
    result = nil
    @room.with_lock do
      return head :forbidden unless @room.reload.accessible_to?(current_user)

      consent = AiRoomAutomationConsent.find_or_initialize_by(room: @room,
        user: current_user)
      actual = consent.persisted? ? consent.revision : 0
      if base != actual
        result = { conflict: actual }
      elsif !consent.persisted? && properties.values.all? { |v| v == false }
        result = { entry: nil, changed: false }
      else
        fingerprint = AiRoomAutomationConsent.fingerprint_for(@room)
        consent.assign_attributes(properties.merge(member_set_fingerprint: fingerprint))
        changed = consent.new_record? || consent.changed?
        if changed
          consent.revision = actual + 1
          consent.save!
        end
        result = { entry: consent, changed: changed }
      end
    end
    if result.key?(:conflict)
      render json: { error: "stale_background_consent",
        current_revision: result[:conflict] }, status: :conflict
    else
      render_snapshot(result[:entry], changed: result[:changed])
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    head :unprocessable_entity
  end

  def render_snapshot(entry, changed: false)
    render json: {
      consent: entry&.public_snapshot(room: @room),
      current_revision: entry&.revision || 0, changed: changed,
      execution: { provider_calls_active: false, unattended_send_active: false,
        scheduled_processing_active: false, configuration_only: true }
    }
  end
end
