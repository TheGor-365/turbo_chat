class ChatAttachmentsController < ApplicationController
  before_action :authenticate_user!

  def show
    attachment = ActiveStorage::Attachment.find_by(id: params[:id])
    return head :not_found unless attachment && attachment.record_type == "Message"

    message = Message.find_by(id: attachment.record_id)
    return head :not_found unless message && message.room.accessible_to?(current_user)

    blob = attachment.blob
    # Defense in depth: legacy or directly attached blobs do not inherit the
    # HTTP upload guard's checks. Never serve unsupported types (e.g. SVG).
    return head :not_found unless Message::ALLOWED_CONTENT_TYPES.include?(blob.content_type)
    return head :not_found if blob.byte_size > Message::MAX_ATTACHMENT_BYTES

    webm = %w[audio/webm video/webm].include?(blob.content_type) &&
      blob.filename.to_s.downcase.end_with?(".webm")
    media_kind = if webm
      blob.open do |file|
        if VoiceWebmInspection.valid?(file)
          :voice
        elsif VideoWebmInspection.valid?(file)
          :video
        end
      end
    end
    return head :not_found if webm && !media_kind

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    if media_kind
      media_type = media_kind == :video ? "video/webm" : "audio/webm"
      response.headers["Accept-Ranges"] = "bytes"
      byte_range = request.headers["Range"].to_s
      if byte_range.present?
        range = /\Abytes=(\d+)-(\d*)\z/.match(byte_range)
        return head 416 unless range

        start_byte = range[1].to_i
        return head 416 if start_byte >= blob.byte_size

        requested_end = range[2].present? ? range[2].to_i : blob.byte_size - 1
        return head 416 if requested_end < start_byte

        end_byte = [requested_end, blob.byte_size - 1, start_byte + 512.kilobytes - 1].min
        response.headers["Content-Range"] = "bytes #{start_byte}-#{end_byte}/#{blob.byte_size}"
        return send_data blob.download_chunk(start_byte..end_byte),
          filename: blob.filename.to_s, type: media_type,
          disposition: "inline", status: :partial_content
      end
    end

    send_data blob.download,
      filename: blob.filename.to_s,
      type: media_kind ? media_type : blob.content_type,
      disposition: media_kind || blob.content_type.start_with?("image/") ? "inline" : "attachment"
  end
end
