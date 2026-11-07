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

  test "room directory renders safely for an account without an uploaded avatar" do
    user = User.create!(email: "no-avatar-room@example.test", password: "testing-secure-password-123")
    assert_not user.avatar.attached?
    sign_in user

    get rooms_path

    assert_response :success
    assert_select 'a.sd-nav__settings[aria-label="Profile & settings"]', count: 1
    assert_select '.sd-sidebar-self__avatar-link [data-profile-initial-user-id]', text: user.chat_label.first.upcase
    assert_select 'nav .sd-nav__identity', count: 0
    assert_select 'img[src^="/user-avatars/"]', count: 0
  end

  test "public room discovery escapes wildcards and hides joined and private rooms" do
    alice = users(:one)
    visible = Room.create!(name: "literal-%_room")
    joined = Room.create!(name: "joined-%_room")
    joined.joinables.create!(user: alice)
    Room.create!(name: "hidden-%_room", is_private: true)
    Room.create!(name: "ordinary-room")
    sign_in alice

    post search_rooms_path, params: { name_search: "%_" }, as: :turbo_stream
    assert_response :success
    assert_includes response.body, visible.name
    assert_not_includes response.body, joined.name
    assert_not_includes response.body, "hidden-%_room"
    assert_not_includes response.body, "ordinary-room"
  end

  test "room search offers Join instead of a forbidden direct navigation" do
    room = Room.create!(name: "community-demo-public")
    sign_in users(:one)

    post search_rooms_path, params: { name_search: "community-demo" }, as: :turbo_stream
    assert_response :success
    assert_select "form[action=?][method=post]", join_room_path(room), count: 1
    assert_select "a[href=?]", room_path(room), count: 0
    assert_includes response.body, room.name
  end

  test "member can join discovered public room and leave without deleting the room" do
    room = Room.create!(name: "join-leave-public")
    user = users(:one)
    sign_in user

    assert_not room.accessible_to?(user)
    get room_path(room)
    assert_response :forbidden

    assert_difference "Joinable.count", 1 do
      post join_room_path(room)
    end
    assert_redirected_to room_path(room)
    assert room.accessible_to?(user)

    get room_path(room)
    assert_response :success
    assert_select "#single_room", count: 1

    assert_no_difference "Room.count" do
      delete leave_room_path(room)
    end
    assert_redirected_to rooms_path
    assert_not room.accessible_to?(user)

    get room_path(room)
    assert_response :forbidden
    post join_room_path(room)
    assert_redirected_to room_path(room)
    assert room.accessible_to?(user)
  end

  test "public room discovery requires at least two characters and caps results" do
    sign_in users(:one)
    25.times { |i| Room.create!(name: "limit-#{i.to_s.rjust(2, '0')}-public") }

    post search_rooms_path, params: { name_search: "limit-" }, as: :turbo_stream
    assert_response :success
    assert_equal 20, response.body.scan("room_list_item").length

    post search_rooms_path, params: { name_search: "l" }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "limit-00-public"

    post search_rooms_path, params: { name_search: "l" * 61 }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "limit-00-public"
  end

  test "people directory searches display names only and never indexes email" do
    alice = users(:one)
    named = User.create!(email: "private-login-needle@example.test",
      password: "testing-secure-password-123", display_name: "Olive Garden")
    other = User.create!(email: "other-needle@example.test",
      password: "testing-secure-password-123", display_name: "Silver Meadow")
    sign_in alice

    get rooms_path, params: { people: "Olive" }
    assert_response :success
    assert_select '#users [data-profile-label-user-id=?]', named.id.to_s, count: 1
    assert_select '#users [data-profile-label-user-id=?]', other.id.to_s, count: 0
    assert_not_includes response.body, named.email

    get rooms_path, params: { people: "private-login-needle" }
    assert_response :success
    assert_select '#users .sd-user-item', count: 0
    assert_select '#users [role=status]', text: /No matching people/

    get rooms_path, params: { people: "O" }
    assert_response :success
    assert_select '#users .sd-user-item', count: 0

    get rooms_path, params: { people: "Olive" * 12 }
    assert_response :success
    assert_select '#users .sd-user-item', count: 0
  end

  test "people directory limits results and treats SQL wildcards literally" do
    alice = users(:one)
    24.times do |i|
      User.create!(email: "directory-#{i}@example.test",
        password: "testing-secure-password-123",
        display_name: "Directory Person #{i}")
    end
    User.create!(email: "wildcard-public@example.test",
      password: "testing-secure-password-123", display_name: "Literal_100")
    sign_in alice

    get rooms_path, params: { people: "Directory" }
    assert_response :success
    assert_select '#users .sd-user-item', count: 20

    get rooms_path, params: { people: "_1" }
    assert_response :success
    assert_select '#users .sd-user-item', count: 1
    assert_select '#users .sd-user-item', text: /Literal_100/
  end

  test "participant can find a private conversation from rooms after reopening app" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    sign_in alice

    get rooms_path
    assert_response :success
    assert_select "#direct-rooms a[href=?]", room_path(room), text: /#{Regexp.escape(bob.chat_label)}/
    assert_not_includes response.body, bob.email, "Directory must not expose another user\'s login email"
    assert_select "#empty-conversation", count: 1

    get room_path(room)
    assert_response :success
    assert_select "#single_room h4", text: bob.chat_label
    assert_select "#direct-rooms a[href=?]", room_path(room), count: 1
  end

  test "unrelated account cannot discover or open another pair's private room" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    stranger = User.create!(email: "outsider-direct@example.test", password: "secure-password-123")
    sign_in stranger

    get rooms_path
    assert_response :success
    assert_select "#direct-rooms a[href=?]", room_path(room), count: 0

    get room_path(room)
    assert_response :forbidden
  end

  test "room navigation does not pretend a session is online without heartbeat evidence" do
    alice = users(:one)
    alice.update!(status: :offline)
    sign_in alice

    get rooms_path
    assert_response :success
    assert_equal "offline", alice.reload.status
    assert_select "[aria-label='Presence unavailable']", minimum: 1
    assert_select ".status-circle.bg-success", count: 0

    get room_path(rooms(:one))
    assert_response :success
    assert_equal "offline", alice.reload.status
    assert_select ".status-circle.bg-success", count: 0
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
