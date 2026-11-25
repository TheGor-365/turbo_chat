# frozen_string_literal: true

class AccountAiEnablementsController < ApplicationController
  wrap_parameters false
  before_action :authenticate_user!
  before_action :no_store
  before_action :limit_updates, only: :update

  rescue_from AiWorkspace::Errors::Unauthorized do
    head :forbidden
  end
  rescue_from AiWorkspace::Errors::InvalidSelection do
    head :unprocessable_entity
  end
  rescue_from AiWorkspace::PersonalEnablement::Conflict do
    head :conflict
  end

  def show
    render json: AiWorkspace::PersonalEnablement.read(actor: current_user).to_h
  end

  def update
    return head :unsupported_media_type unless request.media_type == "application/json"
    body = request.request_parameters
    return head :unprocessable_entity unless body.keys.sort == %w[enabled expected_revision]

    render json: AiWorkspace::PersonalEnablement.write(actor: current_user,
      enabled: body["enabled"], expected_revision: body["expected_revision"]).to_h
  end

  private

  def no_store
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_updates
    enforce_request_limit(scope: "ai-personal-enablement", limit: 12, period: 60.seconds)
  end
end
