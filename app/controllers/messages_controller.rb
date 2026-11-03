class MessagesController < ApplicationController
  before_action :authenticate_user!
  def create
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    @message = current_user.messages.create(
      body: msg_params[:body],
      room_id: @room.id,
      attachments: msg_params[:attachments]
    )
  end

  private

  def msg_params
    params.require(:message).permit(:body, attachments: [])
  end
end
