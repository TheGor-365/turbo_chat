module NotificationsHelper
  # Never use a login email as a public chat label.
  def archive_room_label(room, viewer)
    return room.name unless room.direct_message?

    room.participants.find { |membership| membership.user_id != viewer.id }
      &.user&.chat_label || I18n.t("ui.activity_history.direct_conversation")
  end

  def archive_room_icon(room)
    return "user" if room.direct_message?
    room.private_group? ? "lock" : "globe"
  end

  def archive_attachment_icon(content_type)
    return "image" if content_type.to_s.start_with?("image/")
    return "video" if content_type.to_s.start_with?("video/")
    return "music" if content_type.to_s.start_with?("audio/")
    "file-text"
  end

  def archive_message_icon(message)
    attachment = message.attachments.first
    return "messages" unless attachment

    archive_attachment_icon(attachment.blob.content_type)
  end
end
