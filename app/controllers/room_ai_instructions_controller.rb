# frozen_string_literal: true

# Instructions are shared room data, never automatically passed to xAI.
# An eligible current member may view; group writes require current owner,
# while direct chat members may explicitly edit, with a revision audit log.
class RoomAiInstructionsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_private_room!
  before_action :limit_writes, only: :update

  def show
    render json: snapshot
  end

  def history
    rows = @room.ai_instruction_revisions.includes(:editor)
      .order(revision_number: :desc).limit(15)
    render json: { history: rows.map(&:public_snapshot),
      current_revision: current_revision_number }
  end

  def update
    return head :forbidden unless editable?

    raw = params[:instruction]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys.sort == %w[base_revision content]
    content = raw[:content]
    base = raw[:base_revision]
    return head :unprocessable_entity unless content.is_a?(String) &&
      base.to_s.match?(/\A(?:0|[1-9][0-9]{0,9})\z/)

    @room.with_lock do
      raise AiWorkspace::Errors::Unauthorized unless
        @room.reload.accessible_to?(current_user) && editable?
      previous = latest_revision
      actual = previous&.revision_number || 0
      unless actual == base.to_i
        return render json: { error: "revision_conflict", current: previous&.public_snapshot,
          current_revision: actual }, status: :conflict
      end

      normalized = content.gsub("\r\n", "\n").strip
      if previous&.content == normalized || (previous.nil? && normalized.empty?)
        return render json: { changed: false, current: previous&.public_snapshot,
          current_revision: actual, can_edit: true }
      end

      next_revision = @room.ai_instruction_revisions.build(
        editor: current_user, content: content, revision_number: actual + 1
      )
      unless next_revision.save
        return render json: { error: "invalid_content",
          max_chars: RoomAiInstructionRevision::MAX_CHARS }, status: :unprocessable_entity
      end
      render json: { changed: true, current: next_revision.public_snapshot,
        current_revision: next_revision.revision_number, can_edit: true }
    end
  rescue AiWorkspace::Errors::Unauthorized
    head :forbidden
  end

  private

  def load_private_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def editable?
    RoomAiInstructionRevision.can_edit?(room: @room, user: current_user)
  end

  def latest_revision
    @room.ai_instruction_revisions.includes(:editor)
      .order(revision_number: :desc).first
  end

  def current_revision_number
    @room.ai_instruction_revisions.maximum(:revision_number) || 0
  end

  def snapshot
    row = latest_revision
    { current: row&.public_snapshot, current_revision: row&.revision_number || 0,
      can_edit: editable?, max_chars: RoomAiInstructionRevision::MAX_CHARS,
      provider_inclusion: false }
  end

  def limit_writes
    enforce_request_limit(scope: "room-ai-instructions", limit: 8, period: 60.seconds)
  end
end
