require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def direct_room(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "notification center requires login, stays scoped and never renders DM message body" do
    alice, bob = users(:one), users(:two)
    own_room = direct_room(alice, bob)
    incoming = own_room.messages.create!(user: bob, body: "Private Secret Do Not Render 977")
    note = Notification.find_by!(user: alice, message: incoming)

    stranger = User.create!(email: "notification-peer@example.test", password: "secure-password-123")
    forbidden = direct_room(bob, stranger)
    hidden = forbidden.messages.create!(user: bob, body: "Unrelated Secret Body 188")
    foreign_note = Notification.find_by!(user: stranger, message: hidden)

    get notifications_path
    assert_redirected_to new_user_session_path

    sign_in alice
    get notifications_path
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_select "#notification-list [data-notification-id='#{note.id}']", count: 1
    assert_select "#notification-list [data-notification-id='#{foreign_note.id}']", count: 0
    assert_select "a[href=?]", room_path(own_room, focus: incoming.id), text: "Open"
    assert_not_includes response.body, incoming.body
    assert_not_includes response.body, hidden.body
    assert_not_includes response.body, stranger.email
  end

  test "recipient can mark one event read without modifying conversation cursor" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    first = room.messages.create!(user: bob, body: "First new event")
    second = room.messages.create!(user: bob, body: "Second new event")
    first_note = Notification.find_by!(user: alice, message: first)
    second_note = Notification.find_by!(user: alice, message: second)
    sign_in alice

    post read_notification_path(first_note)
    assert_redirected_to notifications_path
    assert_not_nil first_note.reload.read_at
    assert_nil second_note.reload.read_at
    assert_nil ConversationReadState.find_by(user: alice, room: room)

    get rooms_path
    assert_select "#notifications-nav [data-notification-unread-count='1']", count: 1
    post read_all_notifications_path
    assert_redirected_to notifications_path
    assert_not_nil second_note.reload.read_at
    get rooms_path
    assert_select "#notifications-nav [data-notification-unread-count]", count: 0
  end

  test "room read cursor acknowledges only older matching personal events" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    older = room.messages.create!(user: bob, body: "Read this event")
    newer = room.messages.create!(user: bob, body: "Not yet acknowledged")
    sign_in alice

    post read_room_path(room), params: { last_read_message_id: older.id }
    assert_response :no_content
    assert_not_nil Notification.find_by!(user: alice, message: older).read_at
    assert_nil Notification.find_by!(user: alice, message: newer).read_at
    get rooms_path
    assert_select "#notifications-nav [data-notification-unread-count='1']"
  end

  test "foreign notification ids and former room members cannot mark items read" do
    alice, bob = users(:one), users(:two)
    stranger = User.create!(email: "notification-other@example.test", password: "secure-password-123")
    private_room = direct_room(bob, stranger)
    foreign = private_room.messages.create!(user: bob, body: "Foreign message")
    foreign_note = Notification.find_by!(user: stranger, message: foreign)

    own_room = direct_room(alice, bob)
    incoming = own_room.messages.create!(user: bob, body: "Previously visible")
    own_note = Notification.find_by!(user: alice, message: incoming)

    sign_in alice
    post read_notification_path(foreign_note), params: { user_id: stranger.id }
    assert_response :not_found
    assert_nil foreign_note.reload.read_at

    own_room.participants.where(user: alice).delete_all
    get notifications_path
    assert_response :success
    assert_select "[data-notification-id='#{own_note.id}']", count: 0
    post read_notification_path(own_note)
    assert_response :not_found
    assert_nil own_note.reload.read_at
    post read_all_notifications_path
    assert_redirected_to notifications_path
    assert_nil own_note.reload.read_at
  end

  test "live inbox payload carries count only for the current recipient" do
    alice, bob = users(:one), users(:two)
    room = direct_room(alice, bob)
    room.messages.create!(user: bob, body: "Secret body for notification")
    sign_in alice

    get inbox_rooms_path
    assert_response :success
    json = JSON.parse(response.body)
    assert_includes json.fetch("notifications"), "Notifications"
    assert_includes json.fetch("notifications"), "data-notification-unread-count=\\\"1\\\""
    assert_not_includes json.fetch("notifications"), "Secret body for notification"
    assert_not_includes json.fetch("notifications"), bob.email

    sign_out alice
    sign_in bob
    get inbox_rooms_path
    assert_not_includes JSON.parse(response.body).fetch("notifications"), "data-notification-unread-count"
  end
end
