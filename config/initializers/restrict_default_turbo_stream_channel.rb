# A Turbo signed stream name authenticates the name, not the subscriber.
# Private chat subscriptions must be authorized by RoomMessagesChannel.
# Reject generic Turbo::StreamsChannel subscriptions, including replay of
# previously issued signed stream names.
Rails.application.config.to_prepare do
  Turbo::StreamsChannel.prepend(Module.new do
    def subscribed
      return super unless self.class == Turbo::StreamsChannel

      reject
    end
  end)
end
