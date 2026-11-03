class UserAvatarsController < ApplicationController
  before_action :authenticate_user!

  MAX_AVATAR_BYTES = 5.megabytes
  ALLOWED_AVATAR_TYPES = %w[image/jpeg image/png image/webp].freeze

  def show
    user = User.find_by(id: params[:id])
    return head :not_found unless user&.avatar&.attached?

    blob = user.avatar.blob
    return head :not_found unless ALLOWED_AVATAR_TYPES.include?(blob.content_type)
    return head :not_found if blob.byte_size > MAX_AVATAR_BYTES

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    send_data blob.download,
      type: blob.content_type,
      disposition: "inline"
  end
end
