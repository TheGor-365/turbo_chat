class RoomsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_index_data, only: [:index, :show]

  def index
    render 'index'
  end

  def show
    @single_room = Room.find(params[:id])
    @message = Message.new
    @messages = @single_room.messages.order(created_at: :asc)

    render 'index'
  end

  def create
    @room = Room.create(name: params["room"]["name"])
  end

  private

  def set_index_data
    @room = Room.new
    @rooms = Room.public_rooms
    @users = User.all_except(current_user)
  end
end
