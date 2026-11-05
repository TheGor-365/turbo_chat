class RoomsController < ApplicationController
  include RoomsHelper
  before_action :authenticate_user!
  before_action :set_status
  before_action :limit_room_changes, only: [:create, :join, :leave]
  before_action :limit_searches, only: :search

  def index
    load_sidebar
    render "index"
  end

  def show
    @single_room = Room.find(params[:id])
    return head :forbidden unless @single_room.accessible_to?(current_user)

    @message = Message.new

    pagy_messages = @single_room.messages.includes(:user, :message_reactions, reply_to: :user).order(created_at: :desc)
    @pagy, messages = pagy(pagy_messages, items: 10)
    @messages = messages.reverse

    @conversation_title = if @single_room.is_private?
      @single_room.participants.includes(:user).find { |participant| participant.user_id != current_user.id }&.user&.email || "Direct conversation"
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
    redirect_to @room
  end

  def leave
    @room = Room.public_rooms.find(params[:id])
    current_user.joined_rooms.delete(@room)
    # Existing sockets may hold a previously permitted subscription. Force
    # reconnect so the channel checks current membership again.
    ActionCable.server.remote_connections.where(current_user: current_user).disconnect
    redirect_to rooms_path
  end

  private

  def load_sidebar
    @room = Room.new
    @joined_rooms = current_user.joined_rooms.public_rooms.order(last_message_at: :desc).limit(50)
    @direct_rooms = Room.joins(:participants)
      .where(is_private: true, participants: { user_id: current_user.id })
      .includes(participants: :user)
      .order(last_message_at: :desc, id: :desc)
      .limit(50)
    @rooms = search_rooms
    @users = User.all_except(current_user).order(:email).limit(100)
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
  end

  def limit_room_changes
    enforce_request_limit(scope: "room-change", limit: 15, period: 60.seconds)
  end

  def limit_searches
    enforce_request_limit(scope: "room-search", limit: 30, period: 60.seconds)
  end

  def set_status
    current_user.update(status: User.statuses[:online]) if current_user
  end
end
