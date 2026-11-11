# frozen_string_literal: true

# H4: offline, non-persistent manual review of strictly structured text.
# Every request re-authorizes the current room membership and unanimous grants.
class RoomAiDeliverableReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_room!
  before_action :limit_review, only: :create

  def new
    @revision_text = ""
    @kind = "client_brief"
    # Explicit, synthetic no-provider UI fixture; no stored records or real
    # source IDs are imported, and POST still requires live room-wide consent.
    @text = if params[:demo] == "1"
      "Client Brief\nObjective\nDiagnose an HTTP 422 validation response\n" \
        "Requirements\n- Inspect Rails model validations\n" \
        "- Review permitted request parameters\n" \
        "Open Questions\n- Deadline: To confirm\n- Budget: To confirm"
    else
      ""
    end
  end

  def create
    details = params.require(:deliverable).permit(:kind, :text, :revision_text,
      :intent, decisions: {})
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
