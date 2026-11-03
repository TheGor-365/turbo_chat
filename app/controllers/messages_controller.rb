class MessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    @room = Room.find_by(id: params[:room_id])
    return head :not_found unless @room&.accessible_to?(current_user)

    @message = @room.messages.build(message_params)
    @message.user = current_user

    if @message.save
      redirect_to room_path(@room), status: :see_other
    else
      redirect_to room_path(@room), alert: @message.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def message_params
    params.require(:message).permit(:body, attachments: [])
  end
end
