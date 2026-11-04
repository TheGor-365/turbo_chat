require "test_helper"

class RoomsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "regular users cannot create a public room by forging a POST" do
    sign_in users(:one)

    assert_no_difference({ "Room.count" => 0, "Joinable.count" => 0 }) do
      post rooms_path, params: { room: { name: "forged-room" } }
    end
    assert_response :forbidden
  end

  test "only an admin can create a public room" do
    admin = users(:one)
    admin.update!(role: :admin)
    sign_in admin

    assert_difference({ "Room.count" => 1, "Joinable.count" => 1 }) do
      post rooms_path, params: { room: { name: "admin-public-room", is_private: true } }
    end
    assert_response :redirect
    room = Room.find_by!(name: "admin-public-room")
    assert_not room.is_private?, "Clients must not forge a private room via public room creation"
    assert room.accessible_to?(admin)
  end

  test "guest cannot view rooms" do
    get rooms_path
    assert_redirected_to new_user_session_path
  end

  test "room HTML provides only the authorized channel subscription" do
    sign_in users(:one)
    get room_path(rooms(:one))

    assert_response :success
    assert_select 'turbo-cable-stream-source[channel="RoomMessagesChannel"]', count: 1
    assert_select 'turbo-cable-stream-source[channel="Turbo::StreamsChannel"]', count: 0
    assert_select 'turbo-cable-stream-source[data-room-id]', count: 1
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

  test "leave revokes HTTP room access and message writes until rejoin" do
    room = rooms(:one)
    sign_in users(:one)

    get room_path(room)
    assert_response :success

    delete leave_room_path(room)
    assert_redirected_to rooms_path

    get room_path(room)
    assert_response :forbidden

    assert_no_difference "Message.count" do
      post room_messages_path(room), params: { message: { body: "revoked user" } }
    end
    assert_response :forbidden

    post join_room_path(room)
    assert_redirected_to room_path(room)

    get room_path(room)
    assert_response :success
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
