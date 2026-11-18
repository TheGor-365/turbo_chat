# frozen_string_literal: true

# S3: an explicit per-room dry-run of the server-owned input contract.
# Never calls a provider, reserves budget, creates a message or triggers Send.
# Private source excerpts are returned ONLY to a currently authorized member
# after every present participant has opted into contextual processing.
class RoomAiGenerationInputPreviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_authorized_room!
  before_action :limit_previews

  def create
    raw = params[:preview]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless
      (raw.keys.sort == %w[draft_text mode] ||
        raw.keys.sort == %w[draft_text expected_goal_revision mode])
    mode = raw[:mode]
    return head :unprocessable_entity unless %w[answer beautify].include?(mode)
    draft = raw[:draft_text]
    return head :unprocessable_entity unless draft.instance_of?(String)
    revision = raw[:expected_goal_revision]
    if mode == "answer"
      return head :unprocessable_entity unless revision.is_a?(Integer) &&
        revision.between?(1, 1_000_000_000) && raw.key?(:expected_goal_revision)
    else
      return head :unprocessable_entity if raw.key?(:expected_goal_revision)
    end

    request = AiWorkspace::GenerationOrchestrator::Request.new(
      mode: mode, actor: current_user, room: @room, draft_text: draft,
      request_id: SecureRandom.uuid, confirmed: "1",
      preset_id: (mode == "beautify" ? "polish_clarity" : nil),
      expected_goal_revision: revision
    )
    plan = AiWorkspace::GenerationOrchestrator.new.prepare(request: request)
    compiled = AiWorkspace::GenerationInputContract.build!(
      plan: plan, request: request)

    # Repeat the actual authority gate before serializing any excerpts.
    if mode == "answer"
      AiWorkspace::RoomContextAccess.new.authorize!(
        room: @room.reload, actor: current_user)
      latest = AiConversationGoal.find_by(room: @room, user: current_user, active: true)
      raise AiWorkspace::Errors::InvalidSelection unless latest &&
        latest.revision == compiled.goal_revision &&
        latest.public_snapshot == plan.goal_snapshot
    end

    render json: {
      mode: compiled.mode, contract_version: compiled.version,
      fingerprint: compiled.fingerprint,
      source_ids: compiled.source_ids, goal_revision: compiled.goal_revision,
      goal_purpose: plan.goal_snapshot&.fetch(:purpose),
      sources: (mode == "answer" ? plan.prepared.rows.map { |row|
        { ref: "M#{row.message_id}", speaker: row.speaker, text: row.text }
      } : []),
      draft_preview: (mode == "beautify" ? plan.prepared.rows.first.text : nil),
      provider_called: false, budget_reserved: false,
      message_sent: false, automatic_send_active: false
    }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired
    render json: { error: "context_consent_required" }, status: :unprocessable_entity
  rescue AiWorkspace::Errors::InvalidSelection,
    AiWorkspace::Errors::InvalidPreset
    render json: { error: "invalid_or_stale_input" }, status: :unprocessable_entity
  end

  private

  def load_authorized_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? &&
      @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_previews
    enforce_request_limit(scope: "ai-generation-input-preview", limit: 12,
      period: 60.seconds)
  end
end
