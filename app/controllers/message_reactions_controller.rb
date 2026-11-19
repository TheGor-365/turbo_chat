class MessageReactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_reactions
  before_action :load_authorized_message

  def create
    emoji = params.dig(:reaction, :emoji).to_s
    return head :unprocessable_entity unless MessageReaction::EMOJIS.include?(emoji)

    # PostgreSQL uniqueness, not app-level uniqueness validation, makes
    # double clicks and racing submissions idempotent.
    @message.message_reactions.create_or_find_by!(user: current_user, emoji: emoji)
    respond_to_reaction
  end

  def destroy
    reaction = @message.message_reactions.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless reaction

    reaction.destroy!
    respond_to_reaction
  end

  private

  def load_authorized_message
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    @message = @room.messages.find(params[:message_id])
  end

  def limit_reactions
    enforce_request_limit(scope: "reaction-change", limit: 30, period: 60.seconds)
  end

  def respond_to_reaction
    respond_to do |format|
      format.html { redirect_to room_path(@room) }
      # Immediate feedback, even when this particular tab is reconnecting.
      # Broadcasts independently replace the message for every room member.
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "message_#{@message.id}",
          partial: "messages/message",
          locals: { message: @message.reload, viewer: current_user }
        )
      end
    end
  end
end
