class RoomsController < ApplicationController
  include RoomsHelper
  before_action :authenticate_user!
  before_action :set_status
  before_action :limit_room_changes, only: [:create, :join, :leave]
  before_action :limit_searches, only: :search

  def index
    @room = Room.new
    @joined_rooms = current_user.joined_rooms.order('last_message_at DESC')
    @rooms = search_rooms

    @users = User.all_except(current_user)

    render 'index'
  end

  def show
    @single_room = Room.find(params[:id])
    return head :forbidden unless @single_room.accessible_to?(current_user)

    @message = Message.new

    pagy_messages = @single_room.messages.includes(:user).order(created_at: :desc)
    @pagy, messages = pagy(pagy_messages, items: 10)
    @messages = messages.reverse

    @room = Room.new
    @rooms = search_rooms
    @joined_rooms = current_user.joined_rooms.order('last_message_at DESC')

    @users = User.all_except(current_user)

    render 'index'
  end

  def create
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
