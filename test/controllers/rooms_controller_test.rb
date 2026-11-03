require "test_helper"

class RoomsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @alice = users(:one)
    @bob = users(:two)
    @admin = users(:admin)
  end

  test "anonymous user cannot list or open rooms" do
    get rooms_path
    assert_redirected_to new_user_session_path
    get room_path(rooms(:one))
    assert_redirected_to new_user_session_path
  end

  test "non-admin cannot create a room by POST" do
    sign_in @alice
    assert_no_difference "Room.count" do
      post rooms_path, params: { room: { name: "Not authorized" } }
    end
    assert_response :forbidden
  end

  test "admin can create a room and is joined" do
    sign_in @admin
    assert_difference "Room.count", 1 do
      post rooms_path, params: { room: { name: "Planning" } }
    end
    assert_response :see_other
    assert Room.find_by!(name: "Planning").accessible_to?(@admin)
  end

  test "a public room requires membership before reading its messages" do
    sign_in @alice
    get room_path(rooms(:two))
    assert_response :not_found

    post join_room_path(rooms(:two))
    assert_response :see_other
    get room_path(rooms(:two))
    assert_response :success
  end

  test "outsider cannot read private direct messages or join them" do
    dm = Room.create_private_room([@alice, @bob], "private_#{[@alice.id, @bob.id].sort.join('_')}")
    sign_in @admin
    get room_path(dm)
    assert_response :not_found
    post join_room_path(dm)
    assert_response :not_found
  end

  test "membership changes require POST and DELETE" do
    sign_in @alice
    get join_room_path(rooms(:two))
    assert_response :not_found
    post join_room_path(rooms(:two))
    assert_response :see_other
    delete leave_room_path(rooms(:two))
    assert_response :see_other
    refute rooms(:two).accessible_to?(@alice)
  end
end
