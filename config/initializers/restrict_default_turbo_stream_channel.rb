# A signed stream name authenticates its name, not its subscriber.
# RoomMessagesChannel performs explicit authorization against live membership.
module RejectDefaultTurboStreamSubscriptions
  def subscribed
    return reject if instance_of?(Turbo::StreamsChannel)

    super
  end
end

Rails.application.config.to_prepare do
  unless Turbo::StreamsChannel.ancestors.include?(RejectDefaultTurboStreamSubscriptions)
    Turbo::StreamsChannel.prepend(RejectDefaultTurboStreamSubscriptions)
  end
end
