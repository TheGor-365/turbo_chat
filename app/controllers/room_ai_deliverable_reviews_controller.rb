# frozen_string_literal: true

# H4: offline, non-persistent manual review of strictly structured text.
# Every request re-authorizes the current room membership and unanimous grants.
class RoomAiDeliverableReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_room!
  before_action :limit_review, only: :create

  def new
    @kind = "conversation_summary"
    @review_origin = "local"
    @revision_text = ""
    if params[:demo] == "1"
      # Explicit synthetic fixture, never derived from real room messages.
      @kind = "client_brief"
      @text = "Client Brief\nObjective\nDiagnose an HTTP 422 validation response\n" \
        "Requirements\n- Inspect Rails model validations\n" \
        "- Review permitted request parameters\n" \
        "Open Questions\n- Deadline: To confirm\n- Budget: To confirm"
      @auto_notice = "Synthetic fixture — not derived from this conversation."
    else
      # Default workflow: automatic, read-only evidence draft.
      # It never invokes an external model or persists a document.
      @text = ""
      begin
        bundle = AiWorkspace::ReplyContextBuilder.new.build(
          room: @room, actor: current_user
        )
        result = AiWorkspace::AutomaticClientBriefV1.build!(bundle: bundle)
        @kind = result.kind
        @text = result.text
        @revision_text = result.text
        @document = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
          text: @text, kind: @kind, bundle: bundle
        )
        AiWorkspace::RoomContextAccess.new.authorize!(
          room: @room.reload, actor: current_user
        )
        @links = AiWorkspace::SourceLinks.for_room!(
          room: @room, ids: result.source_ids
        )
        @auto_notice = "Automatic Client Brief from permitted message excerpts. Reported items are not agreed requirements; unknown details need confirmation."
      rescue AiWorkspace::Errors::InvalidSelection
        @auto_notice = "No eligible incoming messages. Paste a document or use a test sample."
      end
    end
  rescue AiWorkspace::Errors::Unauthorized, AiWorkspace::Errors::ConsentRequired
    head :forbidden
  end

  def create
    details = params.require(:deliverable).permit(:kind, :text, :revision_text,
      :intent, :origin, decisions: {})
    # Informational provenance only; never trusted as proof of provider use.
    @review_origin = details[:origin] == "editor" ? "editor" : "local"
    @kind = details[:kind]
    @text = details[:text]
    @revision_text = details[:revision_text].to_s
    bundle = AiWorkspace::ReplyContextBuilder.new.build(
      room: @room, actor: current_user
    )
    @document = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: @text, kind: @kind, bundle: bundle
    )

    if details[:intent] == "compare"
      if details[:decisions].present? || @revision_text.blank?
        raise AiWorkspace::Errors::InvalidSelection, "Invalid comparison."
      end
      @proposed_document = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
        text: @revision_text, kind: @kind, bundle: bundle
      )
      @comparison = AiWorkspace::StructuredDeliverableComparisonV1.compare!(
        original: @document, proposed: @proposed_document
      )
    elsif details[:intent].present? && details[:intent] != "review"
      raise AiWorkspace::Errors::InvalidSelection, "Unknown review operation."
    end

    @revision_text = @text if @revision_text.blank? && details[:intent] != "compare"

    decisions = (details[:decisions] || {}).to_h.reject { |_id, choice| choice.blank? }
    unless decisions.keys.all? { |key| key.match?(/\A[1-9]\d*\z/) } &&
        decisions.keys.map(&:to_i).uniq.size == decisions.size &&
        decisions.keys.all? { |key| @document.entries.any? { |entry| entry.id == key.to_i } }
      raise AiWorkspace::Errors::InvalidSelection, "Invalid review."
    end
    decisions.each do |id, decision|
      @document = AiWorkspace::StructuredDeliverableV1.review!(
        document: @document, entry_id: id.to_i, actor_id: current_user.id,
        decision: decision
      )
    end

    # Membership or participant consent may be revoked during processing.
    AiWorkspace::RoomContextAccess.new.authorize!(
      room: @room.reload, actor: current_user
    )
    referenced_ids = [@document, @proposed_document].compact.flat_map do |document|
      document.entries.flat_map(&:source_ids)
    end.uniq
    @links = referenced_ids.any? ?
      AiWorkspace::SourceLinks.for_room!(room: @room, ids: referenced_ids) : {}
    render :new
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired
    head :forbidden
  rescue AiWorkspace::Errors::InvalidSelection, ActionController::ParameterMissing
    @document = nil
    @comparison = nil
    @text = ""
    @revision_text = ""
    @review_error = "Structured text, comparison or review decision unavailable."
    render :new, status: :unprocessable_entity
  end

  private

  def authorize_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    AiWorkspace::RoomContextAccess.new.authorize!(
      room: @room, actor: current_user
    )
  rescue AiWorkspace::Errors::Unauthorized, AiWorkspace::Errors::ConsentRequired
    head :forbidden
  end

  def limit_review
    enforce_request_limit(scope: "ai-deliverable-review", limit: 12, period: 60.seconds)
  end
end
