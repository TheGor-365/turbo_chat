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
    mode = raw[:mode]
    return head :unprocessable_entity unless %w[answer beautify].include?(mode)
    allowed = mode == "answer" ?
      %w[draft_text expected_goal_revision goal_source mode source_token selected_ids reply_target_id] :
      %w[draft_text mode preset_id writing_language writing_tone]
    return head :unprocessable_entity unless raw.keys.all? { |key| allowed.include?(key) } &&
      raw.keys.include?("mode") && raw.keys.include?("draft_text")
    draft = raw[:draft_text]
    return head :unprocessable_entity unless draft.instance_of?(String)
    revision = raw[:expected_goal_revision]
    if mode == "answer"
      return head :unprocessable_entity unless revision.is_a?(Integer) &&
        revision.between?(1, 1_000_000_000) && raw.key?(:expected_goal_revision)
      return head :unprocessable_entity unless [nil, "room_instructions"].include?(raw[:goal_source])
      selection = raw.key?(:source_token) || raw.key?(:selected_ids)
      if selection
        return head :unprocessable_entity unless raw[:source_token].is_a?(String) &&
          raw[:source_token].bytesize.between?(1, AiWorkspace::SourceSelection::MAX_TOKEN_BYTES) &&
          raw[:selected_ids].is_a?(Array) &&
          raw[:selected_ids].length.between?(1, AiWorkspace::ReplyContextBuilder::MAX_MESSAGES) &&
          raw[:selected_ids].all? { |id| id.instance_of?(Integer) && id.positive? } &&
          raw[:selected_ids].uniq.length == raw[:selected_ids].length
      end
      if raw.key?(:reply_target_id)
        return head :unprocessable_entity unless raw[:reply_target_id].instance_of?(Integer) &&
          raw[:reply_target_id].positive?
      end
    else
      return head :unprocessable_entity if raw.key?(:expected_goal_revision) ||
        raw.key?(:goal_source)
    end

    request = AiWorkspace::GenerationOrchestrator::Request.new(
      mode: mode, actor: current_user, room: @room, draft_text: draft,
      request_id: SecureRandom.uuid, confirmed: "1",
      preset_id: (mode == "beautify" ? raw[:preset_id].presence || "polish_clarity" : nil),
      writing_language: (mode == "beautify" ? raw[:writing_language] : nil),
      writing_tone: (mode == "beautify" ? raw[:writing_tone] : nil),
      expected_goal_revision: revision,
      goal_source: raw[:goal_source],
      source_token: (mode == "answer" ? raw[:source_token] : nil),
      selected_ids: (mode == "answer" ? raw[:selected_ids] : nil),
      reply_target_id: (mode == "answer" ? raw[:reply_target_id] : nil)
    )
    plan = AiWorkspace::GenerationOrchestrator.new.prepare(request: request)
    compiled = AiWorkspace::GenerationInputContract.build!(
      plan: plan, request: request)

    # Repeat the actual authority gate before serializing any excerpts.
    if mode == "answer"
      AiWorkspace::RoomContextAccess.new.authorize!(
        room: @room.reload, actor: current_user)
      latest = if raw[:goal_source] == "room_instructions"
        AiWorkspace::RoomInstructionGoal.load!(room: @room, actor: current_user,
          expected_revision: compiled.goal_revision)
      else
        AiConversationGoal.find_by(room: @room, user: current_user, active: true)
      end
      raise AiWorkspace::Errors::InvalidSelection unless latest &&
        latest.revision == compiled.goal_revision &&
        latest.public_snapshot == plan.goal_snapshot
    end

    # T1: inspect the SAME compiled input that the server would use, rather
    # than a second client-owned or speculative prompt/settings representation.
    payload = JSON.parse(compiled.user_content)
    context = if mode == "answer"
      bundle = plan.prepared
      { policy: "bounded_room_context", candidate_limit: AiWorkspace::ReplyContextBuilder::CANDIDATE_LIMIT,
        scanned: bundle.scanned_messages, included: bundle.rows.size,
        omitted_within_scan: bundle.omitted, truncated: bundle.rows.count(&:truncated),
        max_messages: AiWorkspace::ReplyContextBuilder::MAX_MESSAGES,
        max_context_chars: AiWorkspace::ReplyContextBuilder::MAX_CONTEXT_CHARS,
        reply_to_ref: payload.fetch("reply_to_ref"),
        full_history_covered: false }
    else
      { policy: "own_draft_only", scanned: 0, included: 0,
        omitted_within_scan: 0, truncated: 0, full_history_covered: false }
    end
    effective = {
      schema_version: 1, task: payload.fetch("task"),
      preference_origin: AiWorkspace::WritingPreferenceResolver.for(
        user: current_user, room: @room).source,
      writing_preferences: payload.fetch("writing_preferences"),
      one_shot_options: (mode == "beautify" ? {
        preset_id: payload.fetch("preset_id"),
        preset_version: payload.fetch("preset_version"),
        writing_language: plan.prepared.writing_language,
        writing_tone: plan.prepared.writing_tone
      } : nil),
      room_goal_revision: compiled.goal_revision,
      goal_editable: (mode == "answer" && RoomAiInstructionRevision.can_edit?(room: @room, user: current_user)),
      context: context,
      provider_called: false, budget_reserved: false,
      estimated_cost_usd: nil,
      on_paid_request_reservation_usd: "0.100000",
      separate_manual_send_required: true
    }
    source_token = if mode == "answer"
      raw[:source_token] || AiWorkspace::SourceSelection.issue(
        room: @room, actor: current_user, bundle: plan.prepared, hint: "")
    end
    render json: {
      mode: compiled.mode, contract_version: compiled.version,
      source_token: source_token,
      effective_plan: effective,
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
