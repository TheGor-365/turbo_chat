# frozen_string_literal: true

require "digest"

# H5 first vertical slice: user-triggered, owner-only saved drafts and versions.
# No model calls, background saving, approvals, exports or chat messages.
class RoomAiDeliverablesController < ApplicationController
  before_action :authenticate_user!
  before_action :load_room_and_authorize!
  before_action :load_owned_document!, only: %i[show update]

  def index
    @documents = AiDeliverable.where(room_id: @room.id, owner_id: current_user.id)
      .includes(:revisions).order(updated_at: :desc).limit(30)
    # Listing metadata only. Reading any saved text happens on the
    # separately authorized show endpoint, with live source-author checks.
  end

  def create
    kind, body = draft_params.values_at(:kind, :text)
    @room.with_lock do
      source_ids = validated_source_ids!(kind: kind, body: body)
      @deliverable = AiDeliverable.transaction do
        item = AiDeliverable.create!(room: @room, owner: current_user, kind: kind, state: "draft")
        item.revisions.create!(author: current_user, version: 1,
          body_markdown: body, body_sha256: Digest::SHA256.hexdigest(body),
          source_message_ids: source_ids)
        item
      end
    end
    redirect_to room_ai_deliverable_path(@room, @deliverable),
      notice: "Draft saved. Nothing sent or approved."
  rescue AiWorkspace::Errors::Unauthorized, AiWorkspace::Errors::ConsentRequired
    head :forbidden
  rescue AiWorkspace::Errors::InvalidSelection, ActionController::ParameterMissing,
    ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  def show
    @revisions = @deliverable.revisions.order(version: :desc).to_a
    @current = @revisions.first
    # Re-check that all referenced source messages still belong to this room.
    ids = @revisions.flat_map(&:source_message_ids).uniq
    if ids.any?
      # A saved document must not keep disclosing an ex-member's material.
      # Recheck original source authors against CURRENT participants.
      active_ids = @room.participants.distinct.pluck(:user_id)
      allowed = @room.messages.where(id: ids, user_id: active_ids).count
      raise AiWorkspace::Errors::InvalidSelection unless allowed == ids.size
      @source_links = AiWorkspace::SourceLinks.for_room!(room: @room, ids: ids)
    else
      @source_links = {}
    end
    @selected = @revisions.find { |rev| rev.version == params[:version].to_i } || @current
  rescue AiWorkspace::Errors::InvalidSelection
    head :forbidden
  end

  def update
    expected = Integer(draft_params[:expected_version], exception: false)
    body = draft_params[:text]
    raise AiWorkspace::Errors::InvalidSelection unless expected && body.is_a?(String)
    @room.with_lock do
      @deliverable.lock!
      raise AiWorkspace::Errors::InvalidSelection unless @deliverable.state == "draft"
      current = @deliverable.latest_revision
      raise AiWorkspace::Errors::InvalidSelection unless current.version == expected
      source_ids = validated_source_ids!(kind: @deliverable.kind, body: body)
      @deliverable.revisions.create!(author: current_user, version: expected + 1,
        body_markdown: body, body_sha256: Digest::SHA256.hexdigest(body),
        source_message_ids: source_ids)
    end
    redirect_to room_ai_deliverable_path(@room, @deliverable),
      notice: "New version saved. Nothing sent or approved."
  rescue AiWorkspace::Errors::Unauthorized, AiWorkspace::Errors::ConsentRequired
    head :forbidden
  rescue AiWorkspace::Errors::InvalidSelection, ActionController::ParameterMissing,
    ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private

  def draft_params
    params.require(:deliverable).permit(:kind, :text, :expected_version)
  end

  def load_room_and_authorize!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    authorize_context!
  rescue AiWorkspace::Errors::Unauthorized, AiWorkspace::Errors::ConsentRequired
    head :forbidden
  end

  def authorize_context!
    AiWorkspace::RoomContextAccess.new.authorize!(
      room: @room.reload, actor: current_user
    )
  end

  def load_owned_document!
    @deliverable = AiDeliverable.find_by(id: params[:id], room_id: @room.id,
      owner_id: current_user.id)
    head :not_found unless @deliverable
  end

  def validated_source_ids!(kind:, body:)
    authorize_context!
    bundle = AiWorkspace::ReplyContextBuilder.new.build(
      room: @room, actor: current_user
    )
    doc = AiWorkspace::StructuredDeliverableMarkdownV1.parse!(
      text: body, kind: kind, bundle: bundle
    )
    ids = doc.entries.flat_map(&:source_ids).uniq
    AiWorkspace::SourceLinks.for_room!(room: @room, ids: ids) if ids.any?
    authorize_context!
    ids
  end
end
