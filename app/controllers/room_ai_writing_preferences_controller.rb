# frozen_string_literal: true

# Save only the authenticated user's writing choices for an accessible room.
# No AI provider, history context, shared consent or message Send is invoked.
class RoomAiWritingPreferencesController < ApplicationController
  FIELDS = %w[profile_id writing_style language tone].freeze

  before_action :authenticate_user!
  before_action :load_room!
  before_action :limit_updates, only: :update

  def show
    preference = AiRoomWritingPreference.find_by(user: current_user, room: @room)
    render json: { configured: preference.present?,
      preference: preference&.public_snapshot }
  end

  def update
    # A complete, small, allowlisted snapshot avoids accidental privilege
    # attributes and removes ambiguity around partially merged presets.
    raw = params[:preference]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys.sort == FIELDS.sort

    attributes = raw.permit(*FIELDS).to_h.symbolize_keys
    return head :unprocessable_entity unless attributes[:profile_id].nil? ||
      AiRoomWritingPreference::PROFILE_IDS.include?(attributes[:profile_id])
    return head :unprocessable_entity unless
      AiRoomWritingPreference::STYLE_IDS.include?(attributes[:writing_style]) &&
      AiRoomWritingPreference::LANGUAGES.include?(attributes[:language]) &&
      AiRoomWritingPreference::TONES.include?(attributes[:tone])

    preference = nil
    @room.with_lock do
      raise AiWorkspace::Errors::Unauthorized unless @room.reload.accessible_to?(current_user)
      # A row-level parent lock serializes concurrent member writes. Using
      # create_or_find_by! here would fail on an existing row because model
      # uniqueness validations raise RecordInvalid before DB conflict rescue.
      preference = AiRoomWritingPreference.find_or_initialize_by(
        user: current_user, room: @room
      )
      preference.assign_attributes(attributes)
      preference.save!
    end
    render json: { configured: true, preference: preference.public_snapshot }
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  end

  # Deletes only this member's explicit room override. After a reload, the
  # current account default is inherited; no shared room values change.
  def destroy
    @room.with_lock do
      raise AiWorkspace::Errors::Unauthorized unless @room.reload.accessible_to?(current_user)
      AiRoomWritingPreference.where(user: current_user, room: @room).delete_all
    end
    render json: { configured: false, source: "account_or_system" }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  end

  private

  def load_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_updates
    enforce_request_limit(scope: "ai-writing-preferences", limit: 15, period: 60.seconds)
  end
end
