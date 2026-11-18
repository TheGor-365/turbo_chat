# frozen_string_literal: true

# Offline summaries reuse the existing H4 evidence/brief builders. This action
# is deliberately an explicit, unsaved preview, not a scheduler or Auto Reply.
class RoomAiAutomationPreviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_private_room!
  before_action :limit_previews

  def create
    raw = params[:preview]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys == ["kind"]
    kind = raw[:kind]
    return head :unprocessable_entity unless AiAutomationPolicy::PREVIEW_KINDS.include?(kind)

    builder = AiWorkspace::ReplyContextBuilder.new
    bundle = builder.build(room: @room, actor: current_user)
    result = case kind
    when "conversation_summary"
      AiWorkspace::AutomaticEvidenceDraftV1.build!(bundle: bundle)
    when "client_brief"
      AiWorkspace::AutomaticClientBriefV1.build!(bundle: bundle)
    end

    # Authorization and source ownership are checked again before exposing
    # any derived text; no documents, messages or budget records are written.
    AiWorkspace::RoomContextAccess.new.authorize!(
      room: @room.reload, actor: current_user
    )
    links = AiWorkspace::SourceLinks.for_room!(room: @room, ids: result.source_ids)

    render json: {
      version: 1, kind: result.kind, text: result.text,
      source_message_ids: result.source_ids, source_links: links,
      scanned_messages: bundle.scanned_messages,
      omitted_context_messages: bundle.omitted,
      context_complete: false, provider_called: false,
      saved: false, requires_human_review: true,
      disclaimer: "Extracted excerpts are not validated agreements or full-history conclusions."
    }
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired
    render json: { error: "Current room participant consent is required." },
      status: :unprocessable_entity
  rescue AiWorkspace::Errors::InvalidSelection
    render json: { error: "No safe evidence for this summary type." },
      status: :unprocessable_entity
  end

  private

  def load_private_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_previews
    enforce_request_limit(scope: "ai-automation-preview", limit: 10, period: 60.seconds)
  end
end
