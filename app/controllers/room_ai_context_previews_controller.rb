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

    hint = params.require(:preview).permit(:hint)[:hint]
    bundle = AiWorkspace::ReplyContextBuilder.new.build(
      room: room, actor: current_user, hint: hint
    )
    # Re-evaluate membership/grants immediately before emitting bounded data.
    AiWorkspace::RoomContextAccess.new.authorize!(room: room.reload, actor: current_user)
    links = AiWorkspace::SourceLinks.for_room!(room: room, ids: bundle.source_ids)

    render json: {
      source_token: AiWorkspace::SourceSelection.issue(room: room, actor: current_user,
        bundle: bundle, hint: hint),
      retrieval_version: bundle.retrieval_version,
      scanned_messages: bundle.scanned_messages,
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
    ActionController::ParameterMissing
    render json: { error: "Approved context or valid note unavailable." },
      status: :unprocessable_entity
  end

  private

  def limit_preview
    enforce_request_limit(scope: "ai-context-preview", limit: 12, period: 60.seconds)
  end
end
