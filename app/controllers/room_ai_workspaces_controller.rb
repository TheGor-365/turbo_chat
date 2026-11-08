class RoomAiWorkspacesController < ApplicationController
  before_action :authenticate_user!
  before_action :load_authorized_room
  before_action :limit_previews, only: :preview

  def show
    load_view
  end

  # This never contacts a model or writes a request. It only shows a safe,
  # bounded local preview of text the member explicitly selected.
  def preview
    details = params.require(:review).permit(:operation, message_ids: [])
    @review = AiWorkspace::Scope.new(
      room: @room, actor: current_user,
      operation: details[:operation],
      message_ids: details[:message_ids]
    ).review
    load_view
    render :show
  rescue AiWorkspace::Scope::Unauthorized
    head :forbidden
  rescue AiWorkspace::Scope::InvalidSelection => error
    @review_error = error.message
    load_view
    render :show, status: :unprocessable_entity
  end

  private

  def load_authorized_room
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room
    return head :forbidden unless @room.accessible_to?(current_user)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def limit_previews
    enforce_request_limit(scope: "ai-scope-preview", limit: 12, period: 60.seconds)
  end

  def load_view
    # Full history is NEVER collected implicitly for AI. The selection list
    # is bounded, contains only visible text and does not load file bytes.
    @candidate_messages = @room.messages
      .where("NULLIF(TRIM(messages.body), '') IS NOT NULL")
      .includes(:user).order(created_at: :desc, id: :desc)
      .limit(20).reverse

    @conversation_label = if @room.direct_message?
      @room.participants.includes(:user)
        .find { |membership| membership.user_id != current_user.id }
        &.user&.chat_label || "Direct conversation"
    else
      @room.name
    end
    @selected_ids = @review&.rows&.map(&:message_id) || []
  end
end
