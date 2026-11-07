class RoomNotificationPreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_updates, only: :update

  def update
    room = Room.find(params[:room_id])
    return head :forbidden unless room.accessible_to?(current_user)

    # Only the explicitly submitted boolean is valid; never accept user_id
    # or arbitrary nested preference attributes from the browser.
    requested = params[:muted].to_s
    return head :bad_request unless %w[true false].include?(requested)

    preference = ConversationNotificationPreference.create_or_find_by!(
      user: current_user, room: room
    )
    preference.update!(muted: requested == "true")

    response.headers["Cache-Control"] = "private, no-store"
    respond_to do |format|
      format.html { redirect_to room_path(room), status: :see_other }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "room-notification-preference",
          partial: "rooms/notification_preference",
          locals: { room: room, muted: preference.muted? }
        )
      end
    end
  end

  private

  def limit_updates
    enforce_request_limit(scope: "notification-preferences", limit: 12, period: 60.seconds)
  end
end
