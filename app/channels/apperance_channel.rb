class ApperanceChannel < ApplicationCable::Channel
  def subscribed
    reject unless current_user
  end

  # Never accept client-supplied payloads for a globally broadcast channel.
  # Presence will be reimplemented with server-derived heartbeat/expiry.
  def receive(_data)
    reject
  end
end
