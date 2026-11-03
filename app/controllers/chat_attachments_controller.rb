class ChatAttachmentsController < ApplicationController
  before_action :authenticate_user!

  def show
    attachment = ActiveStorage::Attachment.find_by(id: params[:id])
    return head :not_found unless attachment && attachment.record_type == "Message"

    message = Message.find_by(id: attachment.record_id)
    return head :not_found unless message && message.room.accessible_to?(current_user)

    blob = attachment.blob
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    send_data blob.download,
      filename: blob.filename.to_s,
      type: blob.content_type,
      disposition: blob.content_type.start_with?("image/") ? "inline" : "attachment"
  end
end
