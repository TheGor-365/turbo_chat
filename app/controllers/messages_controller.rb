class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_message_writes, only: :create

  def create
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    @message = @room.messages.build(msg_params)
    @message.user = current_user

    if @message.save
      respond_to do |format|
        format.html { redirect_to room_path(@room) }
        format.turbo_stream { head :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to room_path(@room), alert: @message.errors.full_messages.to_sentence }
        format.turbo_stream { head :unprocessable_entity }
      end
    end
  end

  private

  def limit_message_writes
    enforce_request_limit(scope: "message-create", limit: 30, period: 60.seconds)
  end

  def msg_params
    params.require(:message).permit(:body, attachments: [])
  end
end
