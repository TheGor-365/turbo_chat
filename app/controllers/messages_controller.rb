class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_message_writes, only: %i[create update destroy]
  before_action :load_owned_message, only: %i[edit update destroy]

  def create
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    upload_error = AttachmentUploadGuard.error_for(params.dig(:message, :attachments))
    if upload_error
      return respond_to do |format|
        format.html { redirect_to room_path(@room), alert: upload_error }
        format.turbo_stream { render plain: upload_error, status: :unprocessable_entity }
      end
    end

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

  def edit
  end

  def update
    if @message.update(body_params)
      respond_to do |format|
        format.html { redirect_to room_path(@room), notice: "Message updated" }
        format.turbo_stream { head :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to edit_room_message_path(@room, @message), alert: @message.errors.full_messages.to_sentence }
        format.turbo_stream { render plain: @message.errors.full_messages.to_sentence, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @message.destroy!
    respond_to do |format|
      format.html { redirect_to room_path(@room), notice: "Message deleted" }
      format.turbo_stream { render turbo_stream: turbo_stream.remove("message_#{@message.id}") }
    end
  end

  private

  def load_owned_message
    @room = Room.find(params[:room_id])
    return head :forbidden unless @room.accessible_to?(current_user)

    @message = @room.messages.find(params[:id])
    head :forbidden unless @message.user_id == current_user.id
  end

  def body_params
    params.require(:message).permit(:body)
  end

  def limit_message_writes
    enforce_request_limit(scope: "message-create", limit: 30, period: 60.seconds)
  end

  def msg_params
    params.require(:message).permit(:body, attachments: [])
  end
end
