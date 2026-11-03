class UsersController < ApplicationController
  include RoomsHelper

  before_action :authenticate_user!

  def show
    @user = conversation_partner
    @pending_user = @user
    @room_name = direct_message_name(@user)
    @single_room = Room.find_by(name: @room_name, is_private: true)

    if @single_room
      return head :not_found unless @single_room.accessible_to?(current_user)

      @message = Message.new
      @pagy, messages = pagy(@single_room.messages.includes(:user).order(created_at: :desc), items: 10)
      @messages = messages.reverse
    end

    load_sidebar
    render 'rooms/index'
  end

  # Starting a conversation changes database state: never do this from a GET.
  def start_conversation
    partner = conversation_partner
    room = Room.create_private_room([current_user, partner], direct_message_name(partner))
    redirect_to user_path(partner), status: :see_other
  end

  private

  def conversation_partner
    User.where.not(id: current_user.id).find(params[:id])
  end

  def direct_message_name(partner)
    "private_#{[current_user.id, partner.id].sort.join('_')}"
  end

  def load_sidebar
    @room = Room.new
    @rooms = search_rooms
    @joined_rooms = current_user.joined_rooms.order(last_message_at: :desc)
    @users = User.all_except(current_user).order(:id).limit(100)
  end
end
