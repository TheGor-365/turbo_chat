class PresencePrivacyController < ApplicationController
  before_action :authenticate_user!
  before_action :limit_updates

  def update
    value = params[:share_presence].to_s
    return head :bad_request unless %w[true false].include?(value)

    sharing = value == "true"
    current_user.update!(share_presence: sharing)

    unless sharing
      registry = PresenceRegistry.new
      # A privacy change applies to every DM, across all browser tabs.
      # Only currently joined private rooms are eligible for these events.
      Room.joins(:participants)
        .where(is_private: true, participants: { user_id: current_user.id })
        .distinct.find_each do |room|
        begin
          registry.hide(room_id: room.id, user_id: current_user.id)
        rescue Redis::BaseError => error
          # HTTP snapshots still mask the saved preference, and subsequent
          # socket heartbeats cannot recreate presence while it is disabled.
          Rails.logger.warn("Presence session cleanup unavailable: #{error.class}")
        end

        room.participants.where.not(user_id: current_user.id).pluck(:user_id).each do |recipient_id|
          ActionCable.server.broadcast(
            RoomPresenceChannel.stream_name(room.id, recipient_id),
            { type: "presence_changed" }
          )
        end
      end
    end

    redirect_to edit_user_registration_path, status: :see_other,
      notice: sharing ? "Your DM presence is visible again." : "You now appear offline in direct messages."
  end

  private

  def limit_updates
    enforce_request_limit(scope: "presence-privacy", limit: 8, period: 60.seconds)
  end
end
