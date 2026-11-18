# frozen_string_literal: true

# Owner-only offline suggestion lifecycle. Does not invoke a provider, reserve
# a budget, mark AI-assisted or invoke MessagesController#create.
class RoomAiReplyProposalsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_room!
  before_action :rate_limit_writes, only: %i[create apply destroy]

  def show
    proposal = service.latest!(room: @room, actor: current_user)
    render json: { proposal: proposal&.snapshot, automatic_send_active: false }
  end

  def create
    raw = params[:proposal]
    return head :unprocessable_entity unless raw.is_a?(ActionController::Parameters)
    return head :unprocessable_entity unless raw.keys == ["language"]
    lang = raw[:language]
    return head :unprocessable_entity unless lang.is_a?(String) &&
      AiWorkspace::OfflineReplyProposal::TEMPLATES.key?(lang)

    proposal = service.create!(room: @room, actor: current_user, language: lang)
    render json: { proposal: proposal.snapshot, automatic_send_active: false },
      status: :created
  end

  def apply
    proposal = owned_proposal!
    return unless proposal

    proposal = service.apply!(proposal: proposal, actor: current_user)
    render json: { proposal: proposal.snapshot, applied_to_composer: false,
      automatic_send_active: false }
  end

  def destroy
    proposal = owned_proposal!
    return unless proposal

    service.dismiss!(proposal: proposal, actor: current_user)
    head :no_content
  end

  private

  def service
    @service ||= AiWorkspace::OfflineReplyProposal.new
  end

  def load_room!
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.is_private? && @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def owned_proposal!
    proposal = AiReplyProposal.find_by(id: params[:id],
      room_id: @room.id, user_id: current_user.id)
    head :not_found unless proposal
    proposal
  end

  def rate_limit_writes
    enforce_request_limit(scope: "ai-offline-reply-proposal", limit: 12,
      period: 60.seconds)
  end

  rescue_from AiWorkspace::Errors::Unauthorized,
    AiWorkspace::Errors::ConsentRequired, with: :deny_proposal_access
  rescue_from AiWorkspace::Errors::InvalidSelection,
    AiWorkspace::OfflineReplyProposal::Unavailable,
    ActiveRecord::RecordInvalid, with: :reject_stale_proposal

  def deny_proposal_access
    head :forbidden
  end

  def reject_stale_proposal
    render json: { error: "proposal_unavailable_or_stale",
      automatic_send_active: false }, status: :conflict
  end
end
