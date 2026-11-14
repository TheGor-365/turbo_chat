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

  test "unread inbox filter shows only member-visible rooms with pending incoming messages" do
    alice, bob = users(:one), users(:two)
    outsider = User.create!(email: "inbox-peer@example.test", password: "secure-password-123")
    unread_dm = direct_room(alice, bob)
    read_dm = direct_room(alice, outsider)
    unread_dm.messages.create!(user: bob, body: "Unread DM")
    read_message = read_dm.messages.create!(user: outsider, body: "Already seen")
    ConversationReadState.create!(room: read_dm, user: alice, last_read_message_id: read_message.id)

    public_room = rooms(:one)
    public_room.joinables.find_or_create_by!(user: bob)
    public_room.messages.create!(user: bob, body: "Unread public")
    not_joined = rooms(:two)
    not_joined.messages.create!(user: bob, body: "Other public room")

    sign_in alice
    get rooms_path(inbox: "unread")
    assert_response :success
    assert_select '#inbox-filters a[aria-current="page"][href=?]', rooms_path(inbox: "unread"), text: "Unread"
    assert_select "#direct-rooms a[href=?]", room_path(unread_dm), count: 1
    assert_select "#direct-rooms a[href=?]", room_path(read_dm), count: 0
    assert_select "#rooms a[href^=?]", room_path(public_room), minimum: 1
    assert_select "#rooms a[href^=?]", room_path(not_joined), count: 0

    get room_path(unread_dm, inbox: "unread")
    assert_response :success
    assert_select "#single_room", count: 1
    assert_select "#direct-rooms a[href=?]", room_path(unread_dm), count: 1

    get rooms_path
    assert_response :success
    assert_select "#direct-rooms a[href=?]", room_path(read_dm), count: 1
    assert_select '#inbox-filters a[aria-current="page"]', text: "All"
  end

  test "unread filter finds older public rooms beyond the 50 most recent memberships" do
    alice, bob = users(:one), users(:two)
    old_room = Room.create!(name: "older-unread-beyond-window-public")
    old_room.joinables.create!(user: alice)
    old_room.joinables.create!(user: bob)
    incoming = old_room.messages.create!(user: bob, body: "Unread outside recent fifty")
    old_room.update_columns(last_message_at: 1.year.ago)

    55.times do |i|
      room = Room.create!(name: "recent-public-window-#{i}")
      room.joinables.create!(user: alice)
      room.update_columns(last_message_at: (60 - i).minutes.ago)
    end

    sign_in alice
    get rooms_path
    assert_response :success
    assert_select "#rooms a[href=?]", room_path(old_room), count: 0

    get rooms_path(inbox: "unread")
    assert_response :success
    assert_select "#rooms a[href=?]", room_path(old_room), count: 1
    assert_select "#rooms [data-unread-room-id='#{old_room.id}']", text: "1"
    assert_select "#rooms a[href=?]", room_path(Room.find_by!(name: "recent-public-window-54")), count: 0

    post read_room_path(old_room), params: { last_read_message_id: incoming.id }
    assert_response :no_content
    get rooms_path(inbox: "unread")
    assert_response :success
    assert_select "#rooms a[href=?]", room_path(old_room), count: 0
  end

  test "unread filter finds older direct messages beyond the 50 most recent conversations" do
    alice, bob = users(:one), users(:two)
    old_room = Room.create!(name: "private_unread_beyond_window", is_private: true)
    old_room.participants.create!(user: alice)
    old_room.participants.create!(user: bob)
    old_room.messages.create!(user: bob, body: "Unread private conversation outside recent fifty")
    old_room.update_columns(last_message_at: 1.year.ago)

    55.times do |i|
      room = Room.create!(name: "private_recent_window_#{i}", is_private: true)
      room.participants.create!(user: alice)
      room.participants.create!(user: bob)
      room.update_columns(last_message_at: (60 - i).minutes.ago)
    end

    sign_in alice
    get rooms_path
    assert_response :success
    assert_select "#direct-rooms a[href=?]", room_path(old_room), count: 0

    get rooms_path(inbox: "unread")
    assert_response :success
    assert_select "#direct-rooms a[href=?]", room_path(old_room), count: 1
    assert_select "#direct-rooms [data-unread-room-id='#{old_room.id}']", text: "1"
    assert_select "#direct-rooms a[href=?]", room_path(Room.find_by!(name: "private_recent_window_54")), count: 0
  end

  test "inbox filter navigation does not keep a read conversation open" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    sign_in alice

    get room_path(room)
    assert_response :success
    assert_select "#inbox-filters a[href=?]", rooms_path(inbox: "unread"), text: "Unread", count: 1
    assert_select "#inbox-filters a[href=?]", rooms_path, text: "All", count: 1

    get rooms_path(inbox: "unread")
    assert_response :success
    assert_select '#inbox-filters [aria-current="page"]', text: "Unread", count: 1
    assert_select "#empty-conversation", count: 1
    assert_select "#single_room", count: 0
  end

  test "unread inbox filter shows an empty state after acknowledgements" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    incoming = room.messages.create!(user: bob, body: "Read me")
    sign_in alice

    post read_room_path(room), params: { last_read_message_id: incoming.id }
    assert_response :no_content
    get rooms_path(inbox: "unread")
    assert_response :success
    assert_select "#direct-rooms a[href=?]", room_path(room), count: 0
    assert_select "#direct-rooms a", count: 0
  end

  test "live inbox endpoint stays user-scoped and updates after read acknowledgement" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    incoming = room.messages.create!(user: bob, body: "Private unread inbox marker")
    foreign = User.create!(email: "inbox-third@example.test", password: "secure-password-123")
    hidden = direct_room(bob, foreign)
    hidden.messages.create!(user: bob, body: "Forbidden inbox message")

    get inbox_rooms_path(inbox: "unread")
    assert_redirected_to new_user_session_path

    sign_in alice
    get inbox_rooms_path(inbox: "unread", user_id: bob.id)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    payload = JSON.parse(response.body)
    assert_equal "1", Nokogiri::HTML.fragment(payload.fetch("direct")).at_css("[data-unread-room-id='#{room.id}']")&.text
    assert_includes payload.fetch("direct"), "1 unread messages"
    assert_not_includes payload.fetch("direct"), hidden.name
    assert_not_includes payload.fetch("direct"), "Forbidden inbox message"

    post read_room_path(room), params: { last_read_message_id: incoming.id }
    assert_response :no_content
    get inbox_rooms_path(inbox: "unread")
    assert_response :success
    payload = JSON.parse(response.body)
    assert_empty payload.fetch("direct").strip
    assert_nil Nokogiri::HTML.fragment(payload.fetch("direct")).at_css("[data-unread-room-id='#{room.id}']")

    get inbox_rooms_path
    assert_includes JSON.parse(response.body).fetch("direct"), bob.chat_label
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
