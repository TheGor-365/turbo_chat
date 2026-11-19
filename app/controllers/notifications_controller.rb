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

    # The notification log is not the full conversation archive. Provide
    # authorized links to existing histories even if no event was recorded.
    @history_direct_rooms = Room.direct_messages.joins(:participants)
      .where(participants: { user_id: current_user.id })
      .includes(participants: :user)
      .order(last_message_at: :desc, id: :desc).limit(8)
    @history_private_group_rooms = Room.private_groups.joins(:participants)
      .where(participants: { user_id: current_user.id })
      .order(last_message_at: :desc, id: :desc).limit(8)
    @history_public_rooms = current_user.joined_rooms.public_rooms
      .order(last_message_at: :desc, id: :desc).limit(8)

    load_archive_search

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

  private

  SEARCH_KINDS = %w[all text images documents audio video emails].freeze
  SEARCH_PERIODS = %w[all week month quarter].freeze

  # The archive is a live view of CURRENTLY accessible messages. Never
  # authorize from past notifications, invitation records or cached room IDs.
  def load_archive_search
    @search_query = params[:q].to_s.strip
    @search_kind = SEARCH_KINDS.include?(params[:kind]) ? params[:kind] : "all"
    @search_period = SEARCH_PERIODS.include?(params[:period]) ? params[:period] : "all"
    @search_room_id = params[:room_id].to_s
    @search_room_id = "" unless @search_room_id.match?(/\A[1-9]\d{0,17}\z/)
    @search_active = @search_query.present? || @search_kind != "all" ||
      @search_period != "all" || @search_room_id.present?

    private_ids = Room.where(is_private: true).joins(:participants)
      .where(participants: { user_id: current_user.id }).select(:id)
    public_ids = Room.where(is_private: false).joins(:joinables)
      .where(joinables: { user_id: current_user.id }).select(:id)

    @archive_rooms = Room.where(id: private_ids).or(Room.where(id: public_ids))
      .includes(participants: :user).order(last_message_at: :desc, id: :desc).limit(100)

    @search_results = []
    return unless @search_active
    if @search_query.length > 100
      @search_error = I18n.t("ui.activity_history.error_long")
      return
    end
    if @search_query.present? && @search_query.length < 2
      @search_error = I18n.t("ui.activity_history.error_short")
      return
    end

    # Both sides are scoped subqueries. Even an arbitrary :room_id cannot
    # widen the result set to another person's DM/private group/public room.
    scope = Message.where(room_id: private_ids).or(Message.where(room_id: public_ids))
    scope = scope.where(room_id: @search_room_id.to_i) if @search_room_id.present?

    if @search_query.present?
      escaped = ActiveRecord::Base.sanitize_sql_like(@search_query)
      scope = scope.where(<<~SQL.squish, needle: "%#{escaped}%")
        messages.body ILIKE :needle OR EXISTS (
          SELECT 1 FROM active_storage_attachments AS files
          JOIN active_storage_blobs AS blobs ON blobs.id = files.blob_id
          WHERE files.record_type = 'Message'
            AND files.record_id = messages.id AND files.name = 'attachments'
            AND blobs.filename ILIKE :needle
        )
      SQL
    end

    if @search_kind == "text"
      scope = scope.where("NULLIF(TRIM(messages.body), '') IS NOT NULL")
    elsif @search_kind == "emails"
      # Only addresses mentioned in chat text; this does NOT access inboxes.
      scope = scope.where("messages.body ~* ?",
        "[[:alnum:]_.%+-]+@[[:alnum:].-]+\\.[[:alpha:]]{2,}")
    elsif @search_kind != "all"
      mime_clause = case @search_kind
      when "images" then "blobs.content_type LIKE 'image/%'"
      when "documents" then "blobs.content_type IN ('application/pdf', 'text/plain', 'text/markdown')"
      when "audio" then "blobs.content_type LIKE 'audio/%'"
      when "video" then "blobs.content_type LIKE 'video/%'"
      end
      scope = scope.where(<<~SQL.squish)
        EXISTS (
          SELECT 1 FROM active_storage_attachments AS files
          JOIN active_storage_blobs AS blobs ON blobs.id = files.blob_id
          WHERE files.record_type = 'Message'
            AND files.record_id = messages.id AND files.name = 'attachments'
            AND #{mime_clause}
        )
      SQL
    end

    period_start = case @search_period
    when "week" then 1.week.ago
    when "month" then 1.month.ago
    when "quarter" then 3.months.ago
    end
    scope = scope.where("messages.created_at >= ?", period_start) if period_start

    scope = scope.includes(:user, { room: { participants: :user } },
      attachments_attachments: :blob).order(created_at: :desc, id: :desc)
    @search_pagy, @search_results = pagy(scope, items: 18, page_param: :results_page)
  rescue Pagy::OverflowError
    @search_results = []
    @search_error = I18n.t("ui.activity_history.error_page")
  end
end
