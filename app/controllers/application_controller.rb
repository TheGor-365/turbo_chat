class ApplicationController < ActionController::Base
  before_action :set_rooms

  def set_rooms
    @rooms = Room.public_rooms
  end
end
