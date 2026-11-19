# frozen_string_literal: true

# Account-wide writing defaults; strictly non-sensitive style metadata.
# Separate from room member grants, provider keys, paid calls and Send.
class AccountAiWritingPreferencesController < ApplicationController
  FIELDS = %w[profile_id writing_style language tone].freeze

  before_action :authenticate_user!
  before_action :no_store
  before_action :limit_updates, only: %i[update destroy]

  def show
    item = AiAccountWritingPreference.find_by(user: current_user)
    render json: {configured: item.present?, preference: item&.public_snapshot}
  end

  def update
    raw = params[:preference]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys.sort == FIELDS.sort

    attrs = raw.permit(*FIELDS).to_h.symbolize_keys
    attrs[:profile_id] = nil if attrs[:profile_id] == ""
    return head :unprocessable_entity unless attrs[:profile_id].nil? ||
      AiAccountWritingPreference::PROFILE_IDS.include?(attrs[:profile_id])
    return head :unprocessable_entity unless
      AiAccountWritingPreference::STYLE_IDS.include?(attrs[:writing_style]) &&
      AiAccountWritingPreference::LANGUAGES.include?(attrs[:language]) &&
      AiAccountWritingPreference::TONES.include?(attrs[:tone])

    item = nil
    current_user.with_lock do
      item = AiAccountWritingPreference.find_or_initialize_by(user: current_user)
      item.assign_attributes(attrs)
      item.save!
    end
    respond_success(item)
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  def destroy
    current_user.with_lock do
      AiAccountWritingPreference.where(user: current_user).delete_all
    end
    respond_success(nil)
  end

  private

  def respond_success(item)
    respond_to do |format|
      format.json do
        render json: {configured: item.present?, preference: item&.public_snapshot}
      end
      format.html do
        redirect_to edit_user_registration_path(anchor: "account-writing-defaults"),
          notice: "Writing defaults saved."
      end
    end
  end

  def no_store
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_updates
    enforce_request_limit(scope: "ai-account-writing-preferences", limit: 12, period: 60.seconds)
  end
end
