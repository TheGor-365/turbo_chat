# frozen_string_literal: true

class RoomAiSharedWritingPreferencesController < ApplicationController
  wrap_parameters false

  before_action :authenticate_user!
  before_action :load_room!
  before_action :limit_updates, only: :update

  rescue_from AiWorkspace::Errors::Unauthorized do
    head :forbidden
  end
  rescue_from AiWorkspace::Errors::InvalidPreset, ActiveRecord::RecordInvalid do
    head :unprocessable_entity
  end
  rescue_from AiWorkspace::SharedWritingPreferences::Conflict do
    head :conflict
  end

  def show
    render json: AiWorkspace::SharedWritingPreferences.read(room: @room, actor: current_user)
  end

  def update
    # Only JSON requests with an exact payload; identity is always server-derived.
    return head :unsupported_media_type unless request.media_type == "application/json"
    body = request.request_parameters
    return head :unprocessable_entity unless body.keys.sort == %w[expected_revision preference]
    raw = body["preference"]
    fields = AiWorkspace::WritingPreferenceLayers::FIELDS.map(&:to_s)
    return head :unprocessable_entity unless raw.is_a?(Hash) && raw.keys.sort == fields.sort

    render json: AiWorkspace::SharedWritingPreferences.write(
      room: @room, actor: current_user, attributes: raw.symbolize_keys,
      expected_revision: body["expected_revision"])
  end

  private

  def load_room!
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.private_group? && @room.accessible_to?(current_user)
  end

  def limit_updates
    enforce_request_limit(scope: "ai-shared-writing-preferences", limit: 15, period: 60.seconds)
  end
end
