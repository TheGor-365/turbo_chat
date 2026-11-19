# frozen_string_literal: true

# Public, immutable error copy only: never interpolate user, room or message
# details into an authorization or missing-resource response.
class UiErrorState
  SUPPORTED_STATUSES = [400, 401, 403, 404, 406, 409, 410, 422, 429, 503].freeze

  DEFAULTS = {
    400 => ["Request unavailable", "This request could not be understood. Check it and try again."],
    401 => ["Sign-in required", "Sign in to continue to your conversations."],
    403 => ["Access unavailable", "You may no longer have permission to view this content."],
    404 => ["Content unavailable", "The item may have moved, been deleted or may not be available to your account."],
    406 => ["Format unavailable", "This format cannot be opened here."],
    409 => ["Changes need review", "This item changed while you were working. Check the latest version."],
    410 => ["Content no longer available", "This item is no longer accessible."],
    422 => ["Action not completed", "The action could not be completed. Check your changes and try again."],
    429 => ["Too many requests", "You've reached a temporary limit. Please try again shortly."],
    503 => ["Service temporarily unavailable", "This feature is unavailable right now."]
  }.freeze

  attr_reader :status, :key, :title, :message

  def self.for(status:, controller_path:, room_member:)
    code = Rack::Utils.status_code(status)
    title, message = DEFAULTS.fetch(code)
    key = "http_#{code}"
    if code == 403 && controller_path.start_with?("room_ai_") && room_member
      key = "ai_consent_paused"
      title = "AI access paused"
      message = "A room participant may have changed AI permissions. Recheck room-wide consent before reopening this work."
    elsif code == 403 && controller_path == "rooms"
      key = "room_access_unavailable"
      title = "Conversation unavailable"
      message = "You may no longer have access to this conversation."
    end
    new(status: code, key: key, title: title, message: message)
  end

  def initialize(status:, key:, title:, message:)
    @status, @key, @title, @message = status, key, title, message
  end
end
