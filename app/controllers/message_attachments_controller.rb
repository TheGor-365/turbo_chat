class MessageAttachmentsController < ApplicationController
  before_action :authenticate_user!

  def show
    room = Room.find_by(id: params[:room_id])
    return head :not_found unless room&.accessible_to?(current_user)

    message = room.messages.find_by(id: params[:message_id])
    return head :not_found unless message

    attachment = message.attachments.find_by(id: params[:id])
    return head :not_found unless attachment
    return head :payload_too_large if attachment.blob.byte_size > Message::MAX_ATTACHMENT_BYTES

    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data attachment.blob.download,
      filename: attachment.filename.to_s,
      type: attachment.content_type,
      disposition: attachment.image? ? 'inline' : 'attachment'
  end
end
