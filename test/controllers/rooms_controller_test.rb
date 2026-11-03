require "test_helper"

class RoomsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest cannot view rooms" do
    get rooms_path
    assert_redirected_to new_user_session_path
  end

  test "nonparticipant cannot view private room" do
    sign_in users(:one)
    private_room = Room.create!(name: "private-test", is_private: true)
    private_room.participants.create!(user: users(:two))

    get room_path(private_room)
    assert_response :forbidden
  end

  test "nonmember cannot write to public room" do
    sign_in users(:one)
    assert_no_difference "Message.count" do
      post room_messages_path(rooms(:two)), params: { message: { body: "Unauthorized" } }
    end
    assert_response :forbidden
  end

  test "anonymous cannot write to room" do
    post room_messages_path(rooms(:one)), params: { message: { body: "Unauthorized" } }
    assert_redirected_to new_user_session_path
  end

  test "join and leave are state changing verbs" do
    sign_in users(:one)
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(join_room_path(rooms(:one)), method: :get)
    end

    sign_in users(:one)
    post join_room_path(rooms(:one))
    assert_redirected_to room_path(rooms(:one))
    assert rooms(:one).joinables.exists?(user: users(:one))

    delete leave_room_path(rooms(:one))
    assert_redirected_to rooms_path
    assert_not rooms(:one).joinables.exists?(user: users(:one))
  end
end
