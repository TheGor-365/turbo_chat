class RoomMessagesChannel < Turbo::StreamsChannel
  def subscribed
    room = Room.find_by(id: params[:room_id])
    return reject unless room && current_user && room.accessible_to?(current_user)

    stream_name = verified_stream_name_from_params
    expected_name = self.class.send(:stream_name_from, [room, current_user])
    return reject unless stream_name.present? && stream_name == expected_name

    stream_from stream_name
  end
end
