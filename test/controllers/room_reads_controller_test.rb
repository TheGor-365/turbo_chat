require "test_helper"

class RoomReadsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def direct_room(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "unread counts are per member and do not count own messages" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    incoming = room.messages.create!(user: bob, body: "New DM")
    room.messages.create!(user: alice, body: "Sent by me")
    sign_in alice

    get rooms_path
    assert_response :success
    assert_select "#direct-rooms [data-unread-room-id='#{room.id}']", text: "1"

    post read_room_path(room), params: { last_read_message_id: incoming.id }
    assert_response :no_content
    assert_equal incoming.id, ConversationReadState.find_by!(room: room, user: alice).last_read_message_id

    get rooms_path
    assert_select "#direct-rooms [data-unread-room-id='#{room.id}']", count: 0

    room.messages.create!(user: bob, body: "After read")
    get rooms_path
    assert_select "#direct-rooms [data-unread-room-id='#{room.id}']", text: "1"

    sign_out alice
    sign_in bob
    get rooms_path
    assert_select "#direct-rooms [data-unread-room-id='#{room.id}']", text: "1"
  end

  test "read cursor is monotonic across repeated and stale tab acknowledgements" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    first = room.messages.create!(user: bob, body: "First")
    second = room.messages.create!(user: bob, body: "Second")
    sign_in alice

    post read_room_path(room), params: { last_read_message_id: second.id }
    assert_response :no_content
    post read_room_path(room), params: { last_read_message_id: first.id }
    assert_response :no_content

    state = ConversationReadState.find_by!(room: room, user: alice)
    assert_equal second.id, state.last_read_message_id
    assert_equal 1, ConversationReadState.where(room: room, user: alice).count
  end

  test "nonmembers cannot acknowledge private or unjoined public rooms" do
    alice, bob = users(:one), users(:two)
    private_room = direct_room(alice, bob)
    private_message = private_room.messages.create!(user: bob, body: "Private")
    public_message = rooms(:two).messages.create!(user: bob, body: "Public")
    outsider = User.create!(email: "outsider-read@example.test", password: "secure-password-123")
    sign_in outsider

    assert_no_difference "ConversationReadState.count" do
      post read_room_path(private_room), params: { last_read_message_id: private_message.id }
      assert_response :forbidden
      post read_room_path(rooms(:two)), params: { last_read_message_id: public_message.id }
      assert_response :forbidden
    end
  end

  test "a member cannot mark a guessed foreign or nonexistent message as read" do
    sign_in users(:one)
    other_room_message = rooms(:two).messages.create!(user: users(:two), body: "Unrelated")
    assert_no_difference "ConversationReadState.count" do
      post read_room_path(rooms(:one)), params: { last_read_message_id: other_room_message.id }
      assert_response :unprocessable_entity
      post read_room_path(rooms(:one)), params: { last_read_message_id: 999_999_999 }
      assert_response :unprocessable_entity
      post read_room_path(rooms(:one)), params: { last_read_message_id: "-1" }
      assert_response :bad_request
    end
    assert_not_includes response.body, other_room_message.body
  end

  test "unauthenticated acknowledgement redirects to login" do
    post read_room_path(rooms(:one)), params: { last_read_message_id: messages(:one).id }
    assert_redirected_to new_user_session_path
    assert_equal 0, ConversationReadState.count
  end

  test "joined public rooms expose the correct badge and clear it on read" do
    room = rooms(:one)
    alice = users(:one)
    bob = users(:two)
    room.joinables.find_or_create_by!(user: bob)
    incoming = room.messages.create!(user: bob, body: "Public notification")
    sign_in alice

    get rooms_path
    assert_select "#rooms [data-unread-room-id='#{room.id}']", text: "1"
    post read_room_path(room), params: { last_read_message_id: incoming.id }
    assert_response :no_content
    get rooms_path
    assert_select "#rooms [data-unread-room-id='#{room.id}']", count: 0
  end
end
