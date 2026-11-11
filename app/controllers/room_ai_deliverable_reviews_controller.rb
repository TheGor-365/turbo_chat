# frozen_string_literal: true

# H4: offline, non-persistent manual review of strictly structured text.
# Every request re-authorizes the current room membership and unanimous grants.
class RoomAiDeliverableReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_room!
  before_action :limit_review, only: :create

  def new
    @kind = "client_brief"
    @text = ""
  end

  def create
    details = params.require(:deliverable).permit(:kind, :text, decisions: {})
    @kind = details[:kind]
    @text = details[:text]
    bundle = AiWorkspace::ReplyContextBuilder.new.build(
      room: @room, actor: current_user
    )
    @document = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: @text, kind: @kind, bundle: bundle
    )

    decisions = details[:decisions] || {}
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
    @links = AiWorkspace::SourceLinks.for_room!(
      room: @room, ids: @document.entries.flat_map(&:source_ids).uniq
    ) if @document.entries.any? { |entry| entry.source_ids.any? }
    render :new
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  rescue AiWorkspace::Errors::ConsentRequired
    head :forbidden
  rescue AiWorkspace::Errors::InvalidSelection, ActionController::ParameterMissing
    @document = nil
    @text = ""
    @review_error = "Structured text, evidence or review decision unavailable."
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
