class NotificationsController < ApplicationController
  before_action :authenticate_user!

  # Notification center is an activity log, not a second unread-message
  # engine. No message content is returned outside its current room ACL.
  def index
    @unread_count = Notification.visible_to(current_user).unread.count
    @pagy, @notifications = pagy(
      Notification.visible_to(current_user).includes(:room, message: :user).recent_first,
      items: 20
    )
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
  end

  def read
    # Recipient and current membership must BOTH match, including after a
    # user leaves a room. Return 404 for other users' IDs.
    notification = Notification.visible_to(current_user).find_by(id: params[:id])
    return head :not_found unless notification

    notification.mark_read!
    RoomInboxChannel.notify(current_user)
    redirect_to notifications_path, status: :see_other
  end

  def read_all
    Notification.visible_to(current_user).unread.update_all(
      read_at: Time.current, updated_at: Time.current
    )
    RoomInboxChannel.notify(current_user)
    redirect_to notifications_path, status: :see_other
  end
end
