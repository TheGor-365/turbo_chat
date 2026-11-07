class RoomsController < ApplicationController
  include RoomsHelper
  before_action :authenticate_user!
  before_action :limit_room_changes, only: [:create, :join, :leave]
  before_action :limit_searches, only: :search

  def index
    load_sidebar
    render "index"
  end

  # A server-authoritative, per-user inbox snapshot keeps multiple tabs
  # synchronized without exposing message bodies in websocket events.
  def inbox
    load_inbox
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    render json: {
      direct: render_to_string(partial: "rooms/inbox_direct", formats: [:html]),
      public: render_to_string(partial: "rooms/inbox_public", formats: [:html]),
      notifications: render_to_string(partial: "notifications/nav", formats: [:html],
        locals: { count: @notification_count })
    }
  end

  def show
    @single_room = Room.find(params[:id])
    return head :forbidden unless @single_room.accessible_to?(current_user)

    @message = Message.new

    # Search links open a bounded history window containing the exact hit.
    # A message ID from a different room is never resolved globally.
    if params[:focus].present?
      focus_id = params[:focus].to_s
      return head :bad_request unless focus_id.match?(/\A[1-9]\d{0,17}\z/)

      @focused_message = @single_room.messages.find_by(id: focus_id.to_i)
      return head :not_found unless @focused_message
    end

    pagy_messages = @single_room.messages.includes(:user, :message_reactions, reply_to: :user)
    pagy_messages = pagy_messages.where("messages.id <= ?", @focused_message.id) if @focused_message
    pagy_messages = pagy_messages.order(created_at: :desc, id: :desc)
    @pagy, messages = pagy(pagy_messages, items: 10)
    @messages = messages.reverse

    @room_notification_muted = ConversationNotificationPreference.muted_for?(current_user, @single_room)

    @conversation_title = if @single_room.is_private?
      @single_room.participants.includes(:user).find { |participant| participant.user_id != current_user.id }&.user&.chat_label || "Direct conversation"
    else
      @single_room.name
    end

    load_sidebar
    render "index"
  end

  def create
    return head :forbidden unless current_user.admin?

    @room = Room.create!(name: params.require(:room).fetch(:name))
    @room.joinables.find_or_create_by!(user: current_user)
    RoomInboxChannel.notify(current_user)
    redirect_to @room
  end

  def search
    @rooms = search_rooms

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update('search_results', partial: 'rooms/search_results', locals: { rooms: @rooms })
        ]
      end
    end
  end

  def join
    @room = Room.public_rooms.find(params[:id])
    @room.joinables.find_or_create_by!(user: current_user)
    RoomInboxChannel.notify(current_user)
    redirect_to @room
  end

  def leave
    @room = Room.public_rooms.find(params[:id])
    current_user.joined_rooms.delete(@room)
    RoomInboxChannel.notify(current_user)
    # Existing sockets may hold a previously permitted subscription. Force
    # reconnect so the channel checks current membership again.
    ActionCable.server.remote_connections.where(current_user: current_user).disconnect
    redirect_to rooms_path
  end

  private

  def load_sidebar
    @room = Room.new
    @rooms = search_rooms
    # Search by public display name only; never query or expose login emails.
    # Keep the familiar short demo list until the user enters an explicit search.
    @people_query = params[:people].to_s.squish
    directory = User.all_except(current_user)
    if params.key?(:people)
      if @people_query.length.between?(2, 48)
        sanitized = ActiveRecord::Base.sanitize_sql_like(@people_query)
        directory = directory.where("display_name ILIKE ?", "%#{sanitized}%")
      else
        directory = directory.none
      end
    end
    @users = directory.order(:id).limit(20).to_a
    load_inbox
  end

  def load_inbox
    @notification_count = Notification.visible_to(current_user).unread.count
    @joined_rooms = current_user.joined_rooms.public_rooms.order(last_message_at: :desc).limit(50)
    @direct_rooms = Room.joins(:participants)
      .where(is_private: true, participants: { user_id: current_user.id })
      .includes(participants: :user)
      .order(last_message_at: :desc, id: :desc)
      .limit(50)
    visible_room_ids = (@joined_rooms.map(&:id) + @direct_rooms.map(&:id)).uniq
    @unread_counts = if visible_room_ids.empty?
      {}
    else
      reader_join = Message.sanitize_sql_array([
        "LEFT JOIN conversation_read_states ON conversation_read_states.room_id = messages.room_id AND conversation_read_states.user_id = ?",
        current_user.id
      ])
      Message.where(room_id: visible_room_ids)
        .where.not(user_id: current_user.id)
        .joins(reader_join)
        .where("messages.id > COALESCE(conversation_read_states.last_read_message_id, 0)")
        .group("messages.room_id").count
    end

    # Reuse the authorized, bounded sidebar collections and per-member
    # read cursors. Never filter using a shared messages.read flag.
    @inbox_filter = params[:inbox] == "unread" ? "unread" : "all"
    if @inbox_filter == "unread"
      @joined_rooms = @joined_rooms.select { |room| @unread_counts.fetch(room.id, 0).positive? }
      @direct_rooms = @direct_rooms.select { |room| @unread_counts.fetch(room.id, 0).positive? }
    end
  end

  def limit_room_changes
    enforce_request_limit(scope: "room-change", limit: 15, period: 60.seconds)
  end

  def limit_searches
    enforce_request_limit(scope: "room-search", limit: 30, period: 60.seconds)
  end

end
