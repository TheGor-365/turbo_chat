class RoomsController < ApplicationController
  include RoomsHelper

  before_action :authenticate_user!
  before_action :require_admin!, only: :create

  def index
    load_sidebar
    render 'index'
  end

  def show
    @single_room = Room.find_by(id: params[:id])
    return head :not_found unless @single_room&.accessible_to?(current_user)

    @message = Message.new
    @pagy, messages = pagy(@single_room.messages.includes(:user).order(created_at: :desc), items: 10)
    @messages = messages.reverse
    load_sidebar
    render 'index'
  end

  def create
    @room = Room.new(room_params)

    if @room.save
      Joinable.find_or_create_by!(user: current_user, room: @room)
      redirect_to @room, status: :see_other
    else
      redirect_to rooms_path, alert: @room.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def search
    @rooms = search_rooms
    render turbo_stream: turbo_stream.update(
      'search_results', partial: 'rooms/search_results', locals: { rooms: @rooms }
    )
  end

  def join
    @room = Room.public_rooms.find_by(id: params[:id])
    return head :not_found unless @room

    Joinable.find_or_create_by!(user: current_user, room: @room)
    redirect_to @room, status: :see_other
  end

  def leave
    @room = Room.public_rooms.find_by(id: params[:id])
    return head :not_found unless @room

    Joinable.where(user: current_user, room: @room).delete_all
    redirect_to rooms_path, status: :see_other
  end

  private

  def room_params
    params.require(:room).permit(:name)
  end

  def require_admin!
    head :forbidden unless current_user.admin?
  end

  def load_sidebar
    @room ||= Room.new
    @joined_rooms = current_user.joined_rooms.order(last_message_at: :desc)
    @rooms = search_rooms
    @users = User.all_except(current_user).order(:id).limit(100)
  end
end
