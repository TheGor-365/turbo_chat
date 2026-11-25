# frozen_string_literal: true

# Explicit local inspection of bounded context before a potential paid request.
# Unlike the provider endpoints, this never reserves budget or sends data out.
class RoomAiContextPreviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_preview

  def create
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return head :service_unavailable unless AiWorkspace::ContextReplyGeneration.enabled?

    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room
    return head :forbidden unless room.is_private? && room.accessible_to?(current_user)

    details = params.require(:preview).permit(:hint, :include_room_instructions)
    hint = details[:hint]
    choice = details[:include_room_instructions]
    raise AiWorkspace::Errors::InvalidSelection, "Invalid room-instruction choice." unless
      choice.nil? || %w[0 1].include?(choice)
    access = AiWorkspace::RoomContextAccess::Independent.new
    builder = AiWorkspace::ReplyContextBuilder.new(access: access)
    policy = AiWorkspace::ContextAuthorPolicy.new
    grant_revision = policy.fingerprint(room: room, actor: current_user)
    room_instruction = choice == "1" ? AiWorkspace::RoomInstructionContextV1.load!(
      room: room, actor: current_user) : nil
    bundle = builder.build(
      room: room, actor: current_user, hint: hint
    )
    # Re-evaluate membership/grants immediately before emitting bounded data.
    access.authorize!(room: room.reload, actor: current_user)
    links = AiWorkspace::SourceLinks.for_authorized_room!(room: room, actor: current_user, ids: bundle.source_ids)
    suggestion = AiWorkspace::SmartWorkflowV1.suggest(bundle: bundle, hint: hint)
    preset = AiWorkspace::BusinessPresetRegistryV1.for_task(suggestion.kind)
    business_plan = if preset
      recommended_ids = bundle.rows.reject { |row|
        bundle.selection_reasons.fetch(row.message_id) == "context_fallback"
      }.map(&:message_id)
      AiWorkspace::ContentTransformationV1.new(access: access).plan!(
        room: room, actor: current_user, bundle: bundle, task_kind: suggestion.kind,
        preset_key: preset.key, preset_version: preset.version,
        selected_source_ids: recommended_ids
      )
    end

    token = ActiveRecord::Base.uncached do
      fresh = builder.build(room: room.reload, actor: current_user, hint: hint)
      current_instruction = choice == "1" ? AiWorkspace::RoomInstructionContextV1.load!(
        room: room, actor: current_user) : nil
      unless fresh == bundle && current_instruction == room_instruction &&
          policy.fingerprint(room: room, actor: current_user) == grant_revision
        raise AiWorkspace::Errors::InvalidSelection, "Context changed during preview."
      end
      AiWorkspace::SourceSelection.issue(room: room, actor: current_user,
        bundle: bundle, hint: hint, room_instruction: room_instruction, access: access)
    end
    render json: {
      source_token: token,
      retrieval_version: bundle.retrieval_version,
      room_instruction: room_instruction&.public_snapshot,
      room_instruction_included: room_instruction.present?,
      scanned_messages: bundle.scanned_messages,
      # Derived only from consent-checked excerpts already present in bundle.
      smart_workflow: suggestion.to_h,
      business_plan: business_plan&.to_h,
      omitted_context_messages: bundle.omitted,
      disclaimer: "Lexical matches are not factual verification. Sources are recalculated when Generate is clicked.",
      sources: bundle.rows.map { |row|
        {
          id: row.message_id, speaker: row.speaker, text: row.text,
          truncated: row.truncated,
          reason: bundle.selection_reasons.fetch(row.message_id),
          url: links.fetch(row.message_id)
        }
      }
    }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired, AiWorkspace::Errors::InvalidSelection,
    AiWorkspace::Errors::InvalidPreset,
    ActionController::ParameterMissing
    render json: { error: "Approved context or valid note unavailable." },
      status: :unprocessable_entity
  end

  private

  def limit_preview
    enforce_request_limit(scope: "ai-context-preview", limit: 12, period: 60.seconds)
  end
end
